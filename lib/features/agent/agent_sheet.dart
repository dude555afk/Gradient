import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/agent/agent_models.dart';
import '../../core/agent/agent_service.dart';
import '../../core/diff/simple_diff.dart';
import '../../core/gh/gh_backend.dart';
import '../../core/settings/app_settings.dart';
import '../../core/workspace/workspace_store.dart';

class AgentSheet extends StatefulWidget {
  const AgentSheet({
    super.key,
    required this.workspace,
    this.contextText = '',
  });

  final WorkspaceSelection workspace;
  final String contextText;

  @override
  State<AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<AgentSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _settings = AppSettingsStore();

  final _messages = <AgentMessage>[];
  final _changes = <PendingFileChange>[];
  final _pullRequests = <PendingPullRequest>[];

  bool _busy = false;
  bool _webEnabled = true;

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send([String? forced]) async {
    if (_busy) return;
    final prompt = (forced ?? _controller.text).trim();
    if (prompt.isEmpty) return;

    final settings = await _settings.load();
    if (!settings.providerReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure an AI provider and model first.'),
        ),
      );
      return;
    }

    final apiKey = await _settings.apiKey();
    final githubToken = await _settings.githubToken();

    final history = List<AgentMessage>.from(_messages);

    setState(() {
      _busy = true;
      _messages.add(AgentMessage(role: 'user', content: prompt));
      if (forced == null) _controller.clear();
    });
    _scrollToLatest();

    try {
      final result = await AgentService(
        settings: settings,
        apiKey: apiKey,
        githubToken: githubToken,
        workspace: widget.workspace,
        webEnabled: _webEnabled,
        pageContext: widget.contextText,
      ).run(prompt: prompt, history: history);

      if (!mounted) return;
      setState(() {
        _messages.add(
          AgentMessage(role: 'assistant', content: result.text),
        );
        _changes.addAll(result.fileChanges);
        _pullRequests.addAll(result.pullRequests);
      });
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          AgentMessage(
            role: 'assistant',
            content: _friendlyError(error),
          ),
        );
      });
      _scrollToLatest();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.contains('gh failed')) {
      return 'GitHub operation failed. Gradient could not complete that command.\n\n'
          '${raw.length > 500 ? '${raw.substring(0, 500)}…' : raw}';
    }
    return 'Gradient hit an error while working on this request.\n\n'
        '${raw.length > 500 ? '${raw.substring(0, 500)}…' : raw}';
  }

  Future<void> _apply(PendingFileChange change) async {
    final token = await _settings.githubToken();
    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect GitHub before applying changes.'),
        ),
      );
      return;
    }

    final gh = GhBackend(token: token);
    var branch = change.branch;

    try {
      if (branch == widget.workspace.defaultBranch) {
        branch = 'gradient/change-' +
            DateTime.now().millisecondsSinceEpoch.toString();
        await gh.createBranch(
          fullName: widget.workspace.fullName,
          branch: branch,
          from: widget.workspace.defaultBranch,
        );
      }

      final sha = await gh.writeFile(
        fullName: widget.workspace.fullName,
        path: change.path,
        content: change.newContent,
        message: change.message,
        branch: branch,
        currentSha: change.currentSha,
      );

      if (!mounted) return;
      setState(() {
        _changes.remove(change);
        _messages.add(
          AgentMessage(
            role: 'assistant',
            content: 'Committed ' +
                change.path +
                ' to ' +
                branch +
                '\n' +
                (sha.length > 8 ? sha.substring(0, 8) : sha),
          ),
        );
      });
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _createPr(PendingPullRequest proposal) async {
    final token = await _settings.githubToken();
    if (token.isEmpty) return;
    final gh = GhBackend(token: token);

    try {
      final url = await gh.createPullRequest(
        fullName: widget.workspace.fullName,
        title: proposal.title,
        body: proposal.body,
        head: proposal.head,
        base: proposal.base,
      );
      if (!mounted) return;
      setState(() {
        _pullRequests.remove(proposal);
        _messages.add(
          AgentMessage(
            role: 'assistant',
            content: 'Pull request created: $url',
          ),
        );
      });
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final usableHeight = media.size.height - keyboard;
    final sheetHeight = usableHeight * (keyboard > 0 ? .98 : .88);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded),
                    const SizedBox(width: 8),
                    const Text(
                      'Gradient',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.workspace.fullName,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    ActionChip(
                      label: const Text('Explain repo'),
                      onPressed: _busy
                          ? null
                          : () => _send(
                                'Inspect this repository and explain its architecture, risks, and most useful next steps.',
                              ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      label: const Text('Fix workflow'),
                      onPressed: _busy
                          ? null
                          : () => _send(
                                'Inspect the latest failed GitHub Actions workflow, read the failed job logs, diagnose the root cause, and propose the smallest safe fix.',
                              ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      label: const Text('Review'),
                      onPressed: _busy
                          ? null
                          : () => _send(
                                'Review the current repository state for bugs, regressions, security risks, and cleanup opportunities.',
                              ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (_messages.isEmpty &&
                        _changes.isEmpty &&
                        _pullRequests.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Text(
                          'Ask Gradient about this repo. GitHub operations run through the bundled gh CLI backend.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    for (final message in _messages)
                      Align(
                        alignment: message.role == 'user'
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 640),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: message.role == 'user'
                                ? cs.primaryContainer
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: message.role == 'assistant'
                              ? MarkdownBody(
                                  data: message.content,
                                  selectable: true,
                                  shrinkWrap: true,
                                )
                              : SelectableText(message.content),
                        ),
                      ),
                    for (final change in _changes)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ExpansionTile(
                          leading: const Icon(Icons.difference_rounded),
                          title: Text(change.path),
                          subtitle: Text(change.message),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          children: [
                            Container(
                              width: double.infinity,
                              constraints:
                                  const BoxConstraints(maxHeight: 320),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  buildSimpleDiff(
                                    path: change.path,
                                    oldText: change.oldContent,
                                    newText: change.newContent,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: () => _apply(change),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Apply & commit'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final proposal in _pullRequests)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pull request proposal',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Text(proposal.title),
                              const SizedBox(height: 4),
                              Text(
                                proposal.head + ' → ' + proposal.base,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              if (proposal.body.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                MarkdownBody(
                                  data: proposal.body,
                                  selectable: true,
                                  shrinkWrap: true,
                                ),
                              ],
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed: () => _createPr(proposal),
                                  icon: const Icon(Icons.merge_rounded),
                                  label: const Text('Create PR'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('Gradient is working…'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Material(
                color: cs.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: Column(
                    children: [
                      TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: keyboard > 0 ? 3 : 5,
                        enabled: !_busy,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Ask Gradient about this repo…',
                          border: InputBorder.none,
                        ),
                      ),
                      Row(
                        children: [
                          FilterChip(
                            label: const Text('Web'),
                            selected: _webEnabled,
                            onSelected: _busy
                                ? null
                                : (value) =>
                                    setState(() => _webEnabled = value),
                          ),
                          const Spacer(),
                          IconButton.filled(
                            onPressed: _busy ? null : () => _send(),
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
