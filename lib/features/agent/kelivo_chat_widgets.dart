import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/agent/agent_models.dart';
import '../../shared/gradient_markdown.dart';

class KelivoChatMessage extends StatelessWidget {
  const KelivoChatMessage({
    super.key,
    required this.message,
    required this.onAction,
  });

  final AgentMessage message;
  final ValueChanged<String> onAction;

  bool get _isUser => message.role == 'user';
  bool get _isError => message.role == 'error';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Retry',
              onPressed: () => onAction('retry'),
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment:
            _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment:
                _isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _isUser
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 10,
                        ),
                        child: SelectableText(
                          message.content,
                          style: const TextStyle(height: 1.42),
                        ),
                      ),
                    )
                  : _AssistantParagraphs(text: message.content),
            ),
          ),
          const SizedBox(height: 2),
          _MessageActions(
            isUser: _isUser,
            content: message.content,
            onAction: onAction,
          ),
        ],
      ),
    );
  }
}

class KelivoStreamingMessage extends StatelessWidget {
  const KelivoStreamingMessage({
    super.key,
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'Working…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _AssistantParagraphs(
          text: text,
          streaming: true,
        ),
      ),
    );
  }
}

class KelivoProgressTimeline extends StatelessWidget {
  const KelivoProgressTimeline({
    super.key,
    required this.events,
  });

  final List<AgentProgressEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final visible = events.length > 5
        ? events.sublist(events.length - 5)
        : events;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < visible.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      visible[i].kind == 'done'
                          ? Icons.check_circle_rounded
                          : visible[i].kind == 'model'
                              ? Icons.auto_awesome_rounded
                              : Icons.terminal_rounded,
                      size: 14,
                      color: visible[i].kind == 'done'
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      visible[i].detail.trim().isEmpty
                          ? visible[i].label
                          : '${visible[i].label} · ${visible[i].detail}',
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
    final chunks = splitKelivoAssistantParagraphs(text);
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
            item('delete', Icons.delete_outline_rounded, 'Delete message',
                danger: true),
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
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final Widget? attachmentPreview;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: .42),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
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
                      EdgeInsets.symmetric(horizontal: 4, vertical: 7),
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
                  const Spacer(),
                  SizedBox.square(
                    dimension: 42,
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
    );
  }
}

List<String> splitKelivoAssistantParagraphs(String text) {
  if (text.trim().isEmpty) return <String>[text];

  final lines = text.split('\n');
  final chunks = <String>[];
  final current = <String>[];
  var fenced = false;
  String fenceMarker = '';

  void flush() {
    final value = current.join('\n').trim();
    if (value.isNotEmpty) chunks.add(value);
    current.clear();
  }

  for (final line in lines) {
    final trimmed = line.trimLeft();
    final fence = RegExp(r'^(\x60{3,}|~{3,})').firstMatch(trimmed);
    if (fence != null) {
      final marker = fence.group(1)!;
      if (!fenced) {
        fenced = true;
        fenceMarker = marker[0];
      } else if (marker.startsWith(fenceMarker)) {
        fenced = false;
        fenceMarker = '';
      }
    }

    if (!fenced && line.trim().isEmpty) {
      flush();
    } else {
      current.add(line);
    }
  }

  flush();
  return chunks.isEmpty ? <String>[text] : chunks;
}
