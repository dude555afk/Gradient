import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/agent/agent_models.dart';
import '../../core/agent/kelivo_streaming_content_notifier.dart';
import '../../core/models/model_router.dart';
import '../../core/settings/app_settings.dart';
import '../../shared/gradient_markdown.dart';
import 'assistant_paragraph_splitter.dart';

class KelivoChatMessage extends StatelessWidget {
  const KelivoChatMessage({
    super.key,
    required this.message,
    required this.onAction,
    this.streamingListenable,
  });

  final AgentMessage message;
  final ValueChanged<String> onAction;
  final ValueListenable<StreamingContentData>? streamingListenable;

  bool get _isUser => message.role == 'user';
  bool get _isError => message.role == 'error';

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return _ErrorMessage(
        message: message,
        onRetry: () => onAction('retry'),
      );
    }

    if (_isUser) {
      return _UserMessage(
        message: message,
        onAction: onAction,
      );
    }

    final live = streamingListenable;
    if (live == null) {
      return _AssistantMessage(
        content: message.content,
        onAction: onAction,
      );
    }

    return ValueListenableBuilder<StreamingContentData>(
      valueListenable: live,
      builder: (context, data, _) {
        return _AssistantMessage(
          content: data.content,
          streaming: true,
          progress: data.progress,
          retryStatus: data.retryStatus,
          model: data.model,
          onAction: onAction,
        );
      },
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({
    required this.message,
    required this.onAction,
  });

  final AgentMessage message;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .82,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  child: SelectableText(
                    message.content,
                    style: const TextStyle(height: 1.42),
                  ),
                ),
              ),
            ),
          ),
          _MessageActions(
            isUser: true,
            content: message.content,
            onAction: onAction,
          ),
        ],
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({
    required this.content,
    required this.onAction,
    this.streaming = false,
    this.progress = const [],
    this.retryStatus,
    this.model = '',
  });

  final String content;
  final ValueChanged<String> onAction;
  final bool streaming;
  final List<AgentProgressEvent> progress;
  final RetryStatus? retryStatus;
  final String model;

  @override
  Widget build(BuildContext context) {
    final hasBody = content.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress.isNotEmpty)
            _AssistantTimeline(
              events: progress,
              retryStatus: retryStatus,
              model: model,
            )
          else if (streaming && !hasBody)
            _WorkingRow(model: model),
          if (hasBody)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _AssistantParagraphs(
                text: content,
                streaming: streaming,
              ),
            ),
          if (!streaming && hasBody)
            _MessageActions(
              isUser: false,
              content: content,
              onAction: onAction,
            ),
        ],
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({
    required this.message,
    required this.onRetry,
  });

  final AgentMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lower = message.content.toLowerCase();
    final busy = lower.contains('rate-limit') ||
        lower.contains('rate limit') ||
        lower.contains('429') ||
        lower.contains('busy');

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
      child: Row(
        children: [
          Icon(
            busy ? Icons.schedule_rounded : Icons.error_outline_rounded,
            size: 17,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              busy
                  ? 'Provider is busy right now.'
                  : 'Gradient could not finish that response.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Retry',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _WorkingRow extends StatelessWidget {
  const _WorkingRow({required this.model});

  final String model;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 15,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              model.trim().isEmpty ? 'Working…' : 'Working · $model',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantTimeline extends StatelessWidget {
  const _AssistantTimeline({
    required this.events,
    required this.retryStatus,
    required this.model,
  });

  final List<AgentProgressEvent> events;
  final RetryStatus? retryStatus;
  final String model;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = events.length > 5
        ? events.sublist(events.length - 5)
        : events;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 1, 2, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final event in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    event.kind == 'done'
                        ? Icons.check_circle_rounded
                        : event.kind == 'work'
                            ? Icons.terminal_rounded
                            : Icons.auto_awesome_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.detail.trim().isEmpty
                          ? event.label
                          : '${event.label} · ${event.detail}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          if (retryStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${retryStatus!.label} · '
                '${retryStatus!.attempt}/${retryStatus!.maxRetries}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          if (model.trim().isNotEmpty && visible.isEmpty)
            Text(
              model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}

class _AssistantParagraphs extends StatelessWidget {
  const _AssistantParagraphs({
    required this.text,
    this.streaming = false,
  });

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final chunks = splitAssistantParagraphs(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < chunks.length; i++) ...[
          GradientMarkdown(
            chunks[i],
            streaming: streaming && i == chunks.length - 1,
          ),
          if (i != chunks.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.isUser,
    required this.content,
    required this.onAction,
  });

  final bool isUser;
  final String content;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Copy',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied'),
                duration: Duration(milliseconds: 900),
              ),
            );
          },
          icon: Icon(
            Icons.copy_all_outlined,
            size: 17,
            color: cs.onSurfaceVariant,
          ),
        ),
        IconButton(
          tooltip: 'More',
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final action = await showKelivoMessageActions(
              context,
              isUser: isUser,
            );
            if (action != null) onAction(action);
          },
          icon: Icon(
            Icons.more_horiz_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

Future<String?> showKelivoMessageActions(
  BuildContext context, {
  required bool isUser,
}) {
  Widget item(String value, IconData icon, String label, {bool danger = false}) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: danger ? cs.error : null),
      title: Text(
        label,
        style: TextStyle(color: danger ? cs.error : null),
      ),
      onTap: () => Navigator.pop(context, value),
    );
  }

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUser)
              item('edit', Icons.edit_outlined, 'Edit from here'),
            if (!isUser)
              item('retry', Icons.refresh_rounded, 'Retry response'),
            item('branch', Icons.call_split_rounded, 'Branch conversation'),
            item(
              'delete',
              Icons.delete_outline_rounded,
              'Delete message',
              danger: true,
            ),
          ],
        ),
      ),
    ),
  );
}

class KelivoChatComposer extends StatelessWidget {
  const KelivoChatComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.busy,
    required this.webEnabled,
    required this.onWebChanged,
    required this.selectedRole,
    required this.onRoleChanged,
    required this.onAttach,
    required this.onSend,
    this.attachmentPreview,
    this.maxLines = 5,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool busy;
  final bool webEnabled;
  final ValueChanged<bool> onWebChanged;
  final ModelRole? selectedRole;
  final ValueChanged<ModelRole?> onRoleChanged;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final Widget? attachmentPreview;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amoled = gradientAmoledMode.value &&
        Theme.of(context).brightness == Brightness.dark;
    final composerColor =
        amoled ? const Color(0xFF111113) : cs.surfaceContainerLow;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Material(
        color: composerColor,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: .50),
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: amoled
                  ? Colors.white.withValues(alpha: .10)
                  : cs.outlineVariant.withValues(alpha: .22),
            ),
          ),
          child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 7, 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachmentPreview != null) ...[
                attachmentPreview!,
                const SizedBox(height: 4),
              ],
              TextField(
                controller: controller,
                minLines: 1,
                maxLines: maxLines,
                enabled: enabled,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Message Gradient…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Attach images',
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? onAttach : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                  FilterChip(
                    label: const Text('Web'),
                    selected: webEnabled,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: enabled ? onWebChanged : null,
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<ModelRole?>(
                    tooltip: 'Task routing',
                    enabled: enabled,
                    onSelected: onRoleChanged,
                    itemBuilder: (context) => [
                      const PopupMenuItem<ModelRole?>(
                        value: null,
                        child: Text('Auto routing'),
                      ),
                      for (final role in ModelRole.values)
                        PopupMenuItem<ModelRole?>(
                          value: role,
                          child: Text(role.label),
                        ),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.route_outlined, size: 16),
                      label: Text(selectedRole?.label ?? 'Auto'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const Spacer(),
                  SizedBox.square(
                    dimension: 40,
                    child: IconButton.filled(
                      tooltip: busy ? 'Working' : 'Send',
                      onPressed: enabled ? onSend : null,
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
