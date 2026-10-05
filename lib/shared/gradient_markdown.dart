import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class GradientMarkdown extends StatelessWidget {
  const GradientMarkdown(
    this.data, {
    super.key,
    this.streaming = false,
  });

  final String data;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SelectionArea(
      child: GptMarkdown(
        data,
        streaming: streaming,
        useDollarSignsForLatex: true,
        followLinkColor: true,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 15,
          height: 1.5,
          color: cs.onSurface,
        ),
        codeBuilder: (context, language, code, closed) {
          final label = language.trim().isEmpty ? 'code' : language.trim();
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 7, 4, 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Copy code',
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: code),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 17),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: SelectableText(
                    code,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                      height: 1.45,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
