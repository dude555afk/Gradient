import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/agent/agent_models.dart';
import '../../core/agent/agent_service.dart';
import '../../core/diff/simple_diff.dart';
import '../../core/github/github_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/workspace/workspace_store.dart';
import '../repos/repository_picker_page.dart';
import '../settings/settings_page.dart';
import '../workspace/github_workspace_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _settingsStore = AppSettingsStore();
  final _workspaceStore = WorkspaceStore();

  final List<_UiMessage> _messages = [];
  final List<PendingFileChange> _changes = [];
  final List<PendingPullRequest> _pullRequests = [];

  WorkspaceSelection? _workspace;
  String _modelLabel = 'Auto';
  bool _webEnabled = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restoreWorkspace();
  }

  Future<void> _restoreWorkspace() async {
    final workspace = await _workspaceStore.load();
    if (!mounted) return;
    setState(() => _workspace = workspace);
  }

  Future<void> _pickRepo() async {
    final selection = await Navigator.of(context).push<WorkspaceSelection>(
      MaterialPageRoute<WorkspaceSelection>(
        builder: (_) => const RepositoryPickerPage(),
      ),
    );
    if (selection != null && mounted) {
      setState(() => _workspace = selection);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsPage(),
      ),
    );
  }

  void _openGitHub() {
    final workspace = _workspace;
    final url = workspace == null
        ? 'https://github.com'
        : 'https://github.com/${workspace.fullName}/tree/${workspace.branch}';

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GitHubWorkspacePage(initialUrl: url),
      ),
    );
  }

  Future<void> _send([String? forcedPrompt]) async {
    if (_busy) return;

    final prompt = (forcedPrompt ?? _controller.text).trim();
    if (prompt.isEmpty) return;

    final settings = await _settingsStore.load();
    if (!settings.providerReady) {
      if (!mounted) return;
      await _openSettings();
      return;
    }

    final apiKey = await _settingsStore.apiKey();
    final githubToken = await _settingsStore.githubToken();

    final history = _messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => AgentMessage(role: m.role, content: m.text))
        .toList(growable: false);

    setState(() {
      _busy = true;
      _messages.add(_UiMessage(role: 'user', text: prompt));
      if (forcedPrompt == null) _controller.clear();
    });

    try {
      final result = await AgentService(
        settings: settings,
        apiKey: apiKey,
        githubToken: githubToken,
        workspace: _workspace,
        webEnabled: _webEnabled,
      ).run(
        prompt: prompt,
        history: history,
      );

      var workspace = _workspace;
      if (workspace != null &&
          result.branchUsed != null &&
          result.branchUsed != workspace.branch) {
        workspace = workspace.copyWith(branch: result.branchUsed);
        await _workspaceStore.save(workspace);
      }

      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _modelLabel = result.model;
        _messages.add(
          _UiMessage(role: 'assistant', text: result.text),
        );
        _changes.addAll(result.fileChanges);
        _pullRequests.addAll(result.pullRequests);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _UiMessage(
            role: 'assistant',
            text: 'Agent error: $error',
            error: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyChange(PendingFileChange change) async {
    var workspace = _workspace;
    if (workspace == null) return;

    final token = await _settingsStore.githubToken();
    if (token.isEmpty) {
      if (!mounted) return;
      await _openSettings();
      return;
    }

    final github = GitHubService(token: token);
    try {
      var targetBranch = change.branch;
      if (targetBranch == workspace.defaultBranch) {
        targetBranch =
            'gradient/change-${DateTime.now().millisecondsSinceEpoch}';
        await github.createBranch(
          fullName: workspace.fullName,
          branch: targetBranch,
          from: workspace.defaultBranch,
        );
        workspace = workspace.copyWith(branch: targetBranch);
        await _workspaceStore.save(workspace);
      }

      final commit = await github.writeFile(
        fullName: workspace.fullName,
        path: change.path,
        content: change.newContent,
        message: change.message,
        branch: targetBranch,
        currentSha: change.currentSha,
      );

      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _changes.remove(change);
        _messages.add(
          _UiMessage(
            role: 'assistant',
            text:
                'Committed ${change.path} to $targetBranch\n${commit.substring(0, commit.length.clamp(0, 8))}',
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      github.dispose();
    }
  }

  Future<void> _createPullRequest(PendingPullRequest proposal) async {
    final workspace = _workspace;
    if (workspace == null) return;

    final token = await _settingsStore.githubToken();
    if (token.isEmpty) return;

    final github = GitHubService(token: token);
    try {
      final url = await github.createPullRequest(
        fullName: workspace.fullName,
        title: proposal.title,
        body: proposal.body,
        head: proposal.head,
        base: proposal.base,
      );

      if (!mounted) return;
      setState(() {
        _pullRequests.remove(proposal);
        _messages.add(
          _UiMessage(
            role: 'assistant',
            text: 'Pull request created: $url',
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      github.dispose();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _GradientDrawer(
        workspace: _workspace,
        onPickRepo: _pickRepo,
        onSettings: _openSettings,
        onOpenGitHub: _openGitHub,
      ),
      extendBodyBehindAppBar: true,
      appBar: _FloatingTopBar(
        workspace: _workspace,
        onOpenGitHub: _openGitHub,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_messages.isEmpty && _changes.isEmpty && _pullRequests.isEmpty)
              _EmptyState(
                workspace: _workspace,
                onPrompt: _send,
              )
            else
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 76, 12, 170),
                children: [
                  for (final message in _messages)
                    _MessageBubble(message: message),
                  for (final change in _changes)
                    _ChangeCard(
                      change: change,
                      onApply: () => _applyChange(change),
                    ),
                  for (final proposal in _pullRequests)
                    _PullRequestCard(
                      proposal: proposal,
                      onCreate: () => _createPullRequest(proposal),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Gradient is working…'),
                        ],
                      ),
                    ),
                ],
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _Composer(
                controller: _controller,
                webEnabled: _webEnabled,
                modelLabel: _modelLabel,
                busy: _busy,
                onToggleWeb: () {
                  setState(() => _webEnabled = !_webEnabled);
                },
                onSend: () => _send(),
                onRepo: _pickRepo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _FloatingTopBar({
    required this.workspace,
    required this.onOpenGitHub,
  });

  final WorkspaceSelection? workspace;
  final VoidCallback onOpenGitHub;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = workspace == null
        ? 'No repository selected'
        : '${workspace!.fullName} • ${workspace!.branch}';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: cs.surfaceContainer.withValues(alpha: .82),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Menu',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gradient',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'GitHub workspace',
                      onPressed: onOpenGitHub,
                      icon: const Icon(Icons.call_split_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.workspace,
    required this.onPrompt,
  });

  final WorkspaceSelection? workspace;
  final Future<void> Function(String prompt) onPrompt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 150),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.gradient_rounded, size: 28),
            ),
            const SizedBox(height: 20),
            const Text(
              'What are we building?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              workspace == null
                  ? 'Connect GitHub and choose a repository, or just ask a web/coding question.'
                  : 'Active: ${workspace!.fullName} on ${workspace!.branch}',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _PromptChip(
                  'Fix workflow',
                  onTap: () => onPrompt(
                    'Inspect the latest failed GitHub Actions workflow, read the failed job logs, diagnose the root cause, and propose the smallest safe file changes to fix it.',
                  ),
                ),
                _PromptChip(
                  'Review repo',
                  onTap: () => onPrompt(
                    'Inspect this repository and summarize the architecture, risky areas, and the most important improvements. Read relevant files before answering.',
                  ),
                ),
                _PromptChip(
                  'Open PR',
                  onTap: () => onPrompt(
                    'Review the current branch changes and propose a pull request to the default branch with a concise title and body.',
                  ),
                ),
                _PromptChip(
                  'Search docs',
                  onTap: () => onPrompt(
                    'Search official documentation for the technologies used by this repository and flag any version-sensitive setup issues.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _UiMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: message.error
              ? cs.errorContainer
              : user
                  ? cs.primaryContainer
                  : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText(message.text),
      ),
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({
    required this.change,
    required this.onApply,
  });

  final PendingFileChange change;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final diff = buildSimpleDiff(
      path: change.path,
      oldText: change.oldContent,
      newText: change.newContent,
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        leading: const Icon(Icons.difference_rounded),
        title: Text(change.path),
        subtitle: Text('${change.branch} • ${change.message}'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 360),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                diff,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Nothing is written until you approve.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              FilledButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Apply & commit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PullRequestCard extends StatelessWidget {
  const _PullRequestCard({
    required this.proposal,
    required this.onCreate,
  });

  final PendingPullRequest proposal;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.merge_rounded),
                SizedBox(width: 8),
                Text(
                  'Pull request proposal',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(proposal.title),
            const SizedBox(height: 4),
            Text(
              '${proposal.head} → ${proposal.base}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (proposal.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(proposal.body),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.merge_rounded),
                label: const Text('Create PR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.webEnabled,
    required this.modelLabel,
    required this.busy,
    required this.onToggleWeb,
    required this.onSend,
    required this.onRepo,
  });

  final TextEditingController controller;
  final bool webEnabled;
  final String modelLabel;
  final bool busy;
  final VoidCallback onToggleWeb;
  final VoidCallback onSend;
  final VoidCallback onRepo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            elevation: 2,
            color: cs.surfaceContainerHigh.withValues(alpha: .93),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 6,
                    enabled: !busy,
                    onSubmitted: (_) {
                      if (!busy) onSend();
                    },
                    decoration: const InputDecoration(
                      hintText: 'Ask Gradient…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Choose repository',
                        visualDensity: VisualDensity.compact,
                        onPressed: busy ? null : onRepo,
                        icon: const Icon(Icons.folder_open_rounded),
                      ),
                      FilterChip(
                        label: const Text('Web'),
                        selected: webEnabled,
                        onSelected: busy ? null : (_) => onToggleWeb(),
                        avatar: const Icon(Icons.public_rounded, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Chip(
                          label: Text(
                            modelLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                          avatar: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                          ),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide.none,
                        ),
                      ),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: busy ? null : onSend,
                        icon: busy
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
        ),
      ),
    );
  }
}

class _GradientDrawer extends StatelessWidget {
  const _GradientDrawer({
    required this.workspace,
    required this.onPickRepo,
    required this.onSettings,
    required this.onOpenGitHub,
  });

  final WorkspaceSelection? workspace;
  final VoidCallback onPickRepo;
  final VoidCallback onSettings;
  final VoidCallback onOpenGitHub;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width * .78,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.gradient_rounded),
              title: const Text(
                'Gradient',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: workspace == null
                  ? const Text('No repository')
                  : Text(
                      '${workspace!.fullName}\n${workspace!.branch}',
                      maxLines: 2,
                    ),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onPickRepo();
                },
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Choose repository'),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: const Text('GitHub workspace'),
              subtitle: const Text('Browse the active repo in WebView'),
              onTap: () {
                Navigator.pop(context);
                onOpenGitHub();
              },
            ),
            const Divider(),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                onSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UiMessage {
  const _UiMessage({
    required this.role,
    required this.text,
    this.error = false,
  });

  final String role;
  final String text;
  final bool error;
}
