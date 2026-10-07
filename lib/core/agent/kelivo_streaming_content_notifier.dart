import 'package:flutter/foundation.dart';

import 'agent_models.dart';

@immutable
class RetryStatus {
  const RetryStatus({
    required this.attempt,
    required this.maxRetries,
    required this.retryAt,
    this.label = 'Retrying',
  });

  final int attempt;
  final int maxRetries;
  final DateTime retryAt;
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetryStatus &&
          attempt == other.attempt &&
          maxRetries == other.maxRetries &&
          retryAt == other.retryAt &&
          label == other.label;

  @override
  int get hashCode => Object.hash(attempt, maxRetries, retryAt, label);
}

@immutable
class StreamingContentData {
  const StreamingContentData({
    required this.content,
    required this.totalTokens,
    this.retryStatus,
    this.progress = const [],
    this.model = '',
    this.uiVersion = 0,
  });

  final String content;
  final int totalTokens;
  final RetryStatus? retryStatus;
  final List<AgentProgressEvent> progress;
  final String model;
  final int uiVersion;

  StreamingContentData copyWith({
    String? content,
    int? totalTokens,
    RetryStatus? retryStatus,
    bool clearRetryStatus = false,
    List<AgentProgressEvent>? progress,
    String? model,
    int? uiVersion,
  }) {
    return StreamingContentData(
      content: content ?? this.content,
      totalTokens: totalTokens ?? this.totalTokens,
      retryStatus: clearRetryStatus ? null : (retryStatus ?? this.retryStatus),
      progress: progress ?? this.progress,
      model: model ?? this.model,
      uiVersion: uiVersion ?? this.uiVersion,
    );
  }
}

/// Kelivo-style streaming registry.
///
/// Every assistant response gets its own notifier before generation begins.
/// Updating one response only rebuilds that response widget instead of the
/// whole chat sheet.
class KelivoStreamingContentNotifier {
  final Map<String, ValueNotifier<StreamingContentData>> _notifiers = {};

  ValueNotifier<StreamingContentData> getNotifier(String messageId) {
    return _notifiers.putIfAbsent(
      messageId,
      () => ValueNotifier<StreamingContentData>(
        const StreamingContentData(content: '', totalTokens: 0),
      ),
    );
  }

  bool hasNotifier(String messageId) => _notifiers.containsKey(messageId);

  void markStarted(String messageId, {String model = ''}) {
    final notifier = getNotifier(messageId);
    notifier.value = StreamingContentData(
      content: '',
      totalTokens: 0,
      model: model,
    );
  }

  void updateContent(
    String messageId,
    String content, {
    int? totalTokens,
  }) {
    final notifier = getNotifier(messageId);
    final current = notifier.value;
    notifier.value = current.copyWith(
      content: content,
      totalTokens: totalTokens ?? current.totalTokens + 1,
    );
  }

  void appendContent(String messageId, String delta) {
    if (delta.isEmpty) return;
    final notifier = getNotifier(messageId);
    final current = notifier.value;
    notifier.value = current.copyWith(
      content: current.content + delta,
      totalTokens: current.totalTokens + 1,
    );
  }

  void updateProgress(String messageId, AgentProgressEvent event) {
    final notifier = getNotifier(messageId);
    final current = notifier.value;
    final progress = List<AgentProgressEvent>.from(current.progress);

    final duplicate = progress.isNotEmpty &&
        progress.last.label == event.label &&
        progress.last.detail == event.detail;

    final compact = event.kind == 'retry' || event.kind == 'fallback';
    final lastCompact = progress.isNotEmpty &&
        (progress.last.kind == 'retry' || progress.last.kind == 'fallback');

    if (compact && lastCompact) {
      progress[progress.length - 1] = event;
    } else if (!duplicate) {
      progress.add(event);
      if (progress.length > 8) progress.removeAt(0);
    }

    notifier.value = current.copyWith(progress: progress);
  }

  void updateRetryStatus(String messageId, RetryStatus? status) {
    final notifier = getNotifier(messageId);
    final current = notifier.value;
    notifier.value = current.copyWith(
      retryStatus: status,
      clearRetryStatus: status == null,
    );
  }

  void updateModel(String messageId, String model) {
    final notifier = getNotifier(messageId);
    final current = notifier.value;
    notifier.value = current.copyWith(model: model);
  }

  void forceRebuild(String messageId) {
    final notifier = _notifiers[messageId];
    if (notifier == null) return;
    final current = notifier.value;
    notifier.value = current.copyWith(uiVersion: current.uiVersion + 1);
  }

  void removeNotifier(String messageId) {
    _notifiers.remove(messageId)?.dispose();
  }

  void clear({Set<String> keepMessageIds = const {}}) {
    _notifiers.removeWhere((id, notifier) {
      if (keepMessageIds.contains(id)) return false;
      notifier.dispose();
      return true;
    });
  }

  void dispose() {
    clear();
  }
}
