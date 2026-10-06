import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/openai_compatible_provider.dart';
import '../models/model_router.dart';
import '../settings/app_settings.dart';
import '../workspace/workspace_store.dart';
import 'agent_models.dart';
import 'agent_service.dart';
import 'agent_session_store.dart';
import 'background_agent_runtime.dart';

class AgentTaskSnapshot {
  const AgentTaskSnapshot({
    required this.running,
    required this.streamingText,
    required this.progress,
    required this.conversation,
  });

  final bool running;
  final String streamingText;
  final List<AgentProgressEvent> progress;
  final AgentConversation conversation;

  AgentTaskSnapshot copyWith({
    bool? running,
    String? streamingText,
    List<AgentProgressEvent>? progress,
    AgentConversation? conversation,
  }) {
    return AgentTaskSnapshot(
      running: running ?? this.running,
      streamingText: streamingText ?? this.streamingText,
      progress: progress ?? this.progress,
      conversation: conversation ?? this.conversation,
    );
  }
}

class AgentTaskCoordinator {
  AgentTaskCoordinator._();

  static final AgentTaskCoordinator instance = AgentTaskCoordinator._();

  final AgentSessionStore _sessions = AgentSessionStore();
  final Map<String, ValueNotifier<AgentTaskSnapshot>> _tasks = {};

  ValueListenable<AgentTaskSnapshot>? listenable(String conversationId) =>
      _tasks[conversationId];

  bool isRunning(String conversationId) =>
      _tasks[conversationId]?.value.running ?? false;

  ValueNotifier<AgentTaskSnapshot> launch({
    required AgentConversation conversation,
    required List<AgentMessage> history,
    required String prompt,
    required List<String> imageDataUris,
    required AiSettings settings,
    required String apiKey,
    required String githubToken,
    required WorkspaceSelection workspace,
    required bool webEnabled,
    required String pageContext,
    ModelRole? roleOverride,
  }) {
    final existing = _tasks[conversation.id];
    if (existing != null && existing.value.running) return existing;

    final notifier = existing ??
        ValueNotifier<AgentTaskSnapshot>(
          AgentTaskSnapshot(
            running: true,
            streamingText: '',
            progress: const [],
            conversation: conversation,
          ),
        );

    notifier.value = AgentTaskSnapshot(
      running: true,
      streamingText: '',
      progress: const [],
      conversation: conversation,
    );
    _tasks[conversation.id] = notifier;

    unawaited(
      _run(
        notifier: notifier,
        conversation: conversation,
        history: history,
        prompt: prompt,
        imageDataUris: imageDataUris,
        settings: settings,
        apiKey: apiKey,
        githubToken: githubToken,
        workspace: workspace,
        webEnabled: webEnabled,
        pageContext: pageContext,
        roleOverride: roleOverride,
      ),
    );

    return notifier;
  }

  Future<void> _run({
    required ValueNotifier<AgentTaskSnapshot> notifier,
    required AgentConversation conversation,
    required List<AgentMessage> history,
    required String prompt,
    required List<String> imageDataUris,
    required AiSettings settings,
    required String apiKey,
    required String githubToken,
    required WorkspaceSelection workspace,
    required bool webEnabled,
    required String pageContext,
    required ModelRole? roleOverride,
  }) async {
    final taskId = '${conversation.id}:run';

    try {
      await BackgroundAgentRuntime.start(
        taskId: taskId,
        conversationId: conversation.id,
        title: conversation.title == 'New chat'
            ? workspace.fullName
            : conversation.title,
      );
    } catch (_) {
      // The agent can still run if the Android keep-alive bridge is
      // unavailable, for example in tests or desktop tooling.
    }

    try {
      final result = await AgentService(
        settings: settings,
        apiKey: apiKey,
        githubToken: githubToken,
        workspace: workspace,
        webEnabled: webEnabled,
        pageContext: pageContext,
      ).run(
        prompt: prompt,
        history: history,
        imageDataUris: imageDataUris,
        roleOverride: roleOverride,
        onTextDelta: (delta) {
          if (delta.isEmpty) return;
          final current = notifier.value;
          notifier.value = current.copyWith(
            streamingText: current.streamingText + delta,
          );
        },
        onProgress: (event) {
          final current = notifier.value;
          final progress = List<AgentProgressEvent>.from(current.progress);
          final duplicate = progress.isNotEmpty &&
              progress.last.label == event.label &&
              progress.last.detail == event.detail;
          final compact = event.kind == 'retry' || event.kind == 'fallback';
          final lastCompact = progress.isNotEmpty &&
              (progress.last.kind == 'retry' ||
                  progress.last.kind == 'fallback');

          if (compact && lastCompact) {
            progress[progress.length - 1] = event;
          } else if (!duplicate) {
            progress.add(event);
            if (progress.length > 8) progress.removeAt(0);
          }

          notifier.value = current.copyWith(progress: progress);
          unawaited(
            BackgroundAgentRuntime.update(
              taskId: taskId,
              detail: event.detail.trim().isEmpty
                  ? event.label
                  : '${event.label} • ${event.detail}',
            ).catchError((_) {}),
          );
        },
      );

      final latest = await _sessions.loadById(
            conversation.repoFullName,
            conversation.id,
          ) ??
          conversation;

      final messages = List<AgentMessage>.from(latest.messages);
      if (result.text.trim().isNotEmpty) {
        messages.add(
          AgentMessage(role: 'assistant', content: result.text),
        );
      }

      final used = result.branchUsed?.trim();
      final updated = latest.copyWith(
        messages: messages,
        changes: [
          ...latest.changes,
          ...result.fileChanges,
        ],
        pullRequests: [
          ...latest.pullRequests,
          ...result.pullRequests,
        ],
        taskBranch: used != null &&
                used.isNotEmpty &&
                used != workspace.branch
            ? used
            : latest.taskBranch,
        updatedAt: DateTime.now(),
      );

      await _sessions.save(updated);
      notifier.value = AgentTaskSnapshot(
        running: false,
        streamingText: '',
        progress: const [],
        conversation: updated,
      );
    } catch (error) {
      final latest = await _sessions.loadById(
            conversation.repoFullName,
            conversation.id,
          ) ??
          conversation;
      final messages = List<AgentMessage>.from(latest.messages)
        ..add(
          AgentMessage(
            role: 'error',
            content: _friendlyError(error),
          ),
        );
      final updated = latest.copyWith(
        messages: messages,
        updatedAt: DateTime.now(),
      );
      await _sessions.save(updated);
      notifier.value = AgentTaskSnapshot(
        running: false,
        streamingText: '',
        progress: const [],
        conversation: updated,
      );
    } finally {
      try {
        await BackgroundAgentRuntime.stop(taskId: taskId);
      } catch (_) {}
    }
  }

  String _friendlyError(Object error) {
    if (error is AiProviderException) {
      final detail = error.friendlyMessage;
      if (error.statusCode == 429) {
        return 'The AI provider is busy right now.\n\n$detail';
      }
      return 'The AI provider could not complete this request.\n\n$detail';
    }

    final raw = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.contains('gh failed')) {
      return 'GitHub could not complete that operation.\n\n'
          '${raw.length > 260 ? '${raw.substring(0, 260)}…' : raw}';
    }
    return 'Gradient could not finish this request.\n\n'
        '${raw.length > 260 ? '${raw.substring(0, 260)}…' : raw}';
  }
}
