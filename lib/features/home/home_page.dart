import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/agent/agent_models.dart';
import '../../core/agent/agent_service.dart';
import '../../core/diff/simple_diff.dart';
import '../../core/github/github_page_context.dart';
import '../../core/github/github_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/workspace/workspace_store.dart';
import '../settings/settings_page.dart';

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
  final Map<String, String> _defaultBranchCache = {};

  late final WebViewController _webView;

  GitHubPageContext _page =
      GitHubPageContext.parse('https://github.com');
  WorkspaceSelection? _workspace;
  String _pageTitle = 'GitHub';
  String _pageExcerpt = '';
  String _modelLabel = 'Auto';
  bool _webEnabled = true;
  bool _busy = false;
  bool _assistantOpen = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'GradientPage',
        onMessageReceived: _onPageMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress / 100);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _syncUrl(url);
          },
          onPageFinished: (url) async {
            await _syncUrl(url);
            await _captureVisiblePage();
          },
        ),
      )
      ..loadRequest(Uri.parse('https://github.com'));
  }

  void _onPageMessage(JavaScriptMessage message) {
    try {
      final decoded = jsonDecode(message.message) as Map<String, dynamic>;
      final title = decoded['title'] as String? ?? 'GitHub';
      var text = decoded['text'] as String? ?? '';

      if (_page.mayContainSensitiveFile) {
        text = '';
      } else {
        text = _redact(text);
      }

      if (!mounted) return;
      setState(() {
        _pageTitle = title;
        _pageExcerpt = text;
      });
    } catch (_) {
      // A changing GitHub DOM should never break the browser itself.
    }
  }

  String _redact(String text) {
    return text
        .replaceAll(
          RegExp(r'github_pat_[A-Za-z0-9_]+'),
          '[REDACTED_GITHUB_TOKEN]',
        )
        .replaceAll(
          RegExp(r'gh[pousr]_[A-Za-z0-9]+'),
          '[REDACTED_GITHUB_TOKEN]',
        )
        .replaceAll(
          RegExp(r'sk-[A-Za-z0-9_-]{16,}'),
          '[REDACTED_API_KEY]',
        );
  }

  Future<void> _captureVisiblePage() async {
    const script = r'''
(() => {
  const body = document.body?.innerText || '';
  const text = body.replace(/\s+/g, ' ').trim().slice(0, 12000);
  GradientPage.postMessage(JSON.stringify({
    title: document.title || 'GitHub',
    text
  }));
})();
''';
    try {
      await _webView.runJavaScript(script);
    } catch (_) {
      // Page context is optional. Browsing must keep working without it.
    }
  }

  Future<void> _syncUrl(String url) async {
    final parsed = GitHubPageContext.parse(url);

    if (!mounted) return;
    setState(() => _page = parsed);

    final fullName = parsed.fullName;
    if (fullName == null) {
      if (mounted) setState(() => _workspace = null);
      return;
    }

    var defaultBranch = _defaultBranchCache[fullName];
    if (defaultBranch == null) {
      final token = await _settingsStore.githubToken();
      final github = GitHubService(token: token);
      try {
        final repo = await github.repository(fullName);
        defaultBranch =
            repo['default_branch'] as String? ?? 'main';
        _defaultBranchCache[fullName] = defaultBranch;
      } catch (_) {
        defaultBranch = 'main';
      } finally {
        github.dispose();
      }
    }

    final selection = WorkspaceSelection(
      fullName: fullName,
      defaultBranch: defaultBranch,
      branch: parsed.branch ?? defaultBranch,
    );
    await _workspaceStore.save(selection);

    if (!mounted) return;
    setState(() => _workspace = selection);
  }

  String _agentPageContext() {
    final buffer = StringBuffer()
      ..writeln(_page.describe())
      ..writeln('Page title: $_pageTitle');

    if (_pageExcerpt.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Visible GitHub page excerpt:')
        ..writeln(_pageExcerpt);
    } else if (_page.mayContainSensitiveFile) {
      buffer.writeln(
        'Visible page text withheld because the current path may contain sensitive configuration.',
      );
    }

    return buffer.toString().trim();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsPage(),
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
      _assistantOpen = true;
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
        pageContext: _agentPageContext(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Connect GitHub in Gradient settings before committing.',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: _openSettings,
          ),
        ),
      );
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
      await _webView.reload();
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
    if (token.isEmpty) {
      if (!mounted) return;
      await _openSettings();
      return;
    }

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

      if (url.isNotEmpty) {
        await _webView.loadRequest(Uri.parse(url));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      github.dispose();
    }
  }

  String _primaryQuickAction() {
    return switch (_page.kind) {
      'actions' => 'Inspect the current Actions page. Find the latest failed workflow, read the failed job logs, diagnose the root cause, and propose the smallest safe fix.',
      'pull_request' => 'Review the pull request currently open in GitHub. Inspect the changed code, identify regressions or risks, and suggest concrete fixes.',
      'issue' => 'Analyze the issue currently open in GitHub. Inspect relevant repository files and propose an implementation plan.',
      'file' => 'Explain the file currently open in GitHub, focusing on what it does, risks, and improvements.',
      _ => 'Inspect the current GitHub repository page and explain the project structure, current state, and most useful next coding action.',
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: WebViewWidget(controller: _webView),
            ),
            if (_progress < 1)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(value: _progress),
              ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: _BrowserBar(
                page: _page,
                title: _pageTitle,
                onBack: () async {
                  if (await _webView.canGoBack()) {
                    await _webView.goBack();
                  }
                },
                onForward: () async {
                  if (await _webView.canGoForward()) {
                    await _webView.goForward();
                  }
                },
                onHome: () => _webView.loadRequest(
                  Uri.parse('https://github.com'),
                ),
                onReload: _webView.reload,
                onSettings: _openSettings,
              ),
            ),
            if (!_assistantOpen)
              Positioned(
                right: 16,
                bottom: 22,
                child: FloatingActionButton.extended(
                  heroTag: 'gradient-ai',
                  onPressed: () {
                    setState(() => _assistantOpen = true);
                  },
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Gradient'),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              left: 8,
              right: 8,
              bottom: _assistantOpen ? 8 : -620,
              height: MediaQuery.sizeOf(context).height * .67,
              child: _AssistantPanel(
                controller: _controller,
                messages: _messages,
                changes: _changes,
                pullRequests: _pullRequests,
                busy: _busy,
                webEnabled: _webEnabled,
                modelLabel: _modelLabel,
                page: _page,
                onClose: () {
                  setState(() => _assistantOpen = false);
                },
                onSend: () => _send(),
                onQuickAction: () => _send(_primaryQuickAction()),
                onToggleWeb: () {
                  setState(() => _webEnabled = !_webEnabled);
                },
                onApplyChange: _applyChange,
                onCreatePullRequest: _createPullRequest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserBar extends StatelessWidget {
  const _BrowserBar({
    required this.page,
    required this.title,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onReload,
    required this.onSettings,
  });

  final GitHubPageContext page;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onHome;
  final VoidCallback onReload;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = page.fullName ?? 'github.com';

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          elevation: 2,
          color: cs.surface.withValues(alpha: .90),
          child: SizedBox(
            height: 54,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: onForward,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                Expanded(
                  child: InkWell(
                    onTap: onHome,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
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
                  ),
                ),
                IconButton(
                  tooltip: 'Reload',
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Gradient settings',
                  onPressed: onSettings,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantPanel extends StatelessWidget {
  const _AssistantPanel({
    required this.controller,
    required this.messages,
    required this.changes,
    required this.pullRequests,
    required this.busy,
    required this.webEnabled,
    required this.modelLabel,
    required this.page,
    required this.onClose,
    required this.onSend,
    required this.onQuickAction,
    required this.onToggleWeb,
    required this.onApplyChange,
    required this.onCreatePullRequest,
  });

  final TextEditingController controller;
  final List<_UiMessage> messages;
  final List<PendingFileChange> changes;
  final List<PendingPullRequest> pullRequests;
  final bool busy;
  final bool webEnabled;
  final String modelLabel;
  final GitHubPageContext page;
  final VoidCallback onClose;
  final VoidCallback onSend;
  final VoidCallback onQuickAction;
  final VoidCallback onToggleWeb;
  final Future<void> Function(PendingFileChange change) onApplyChange;
  final Future<void> Function(PendingPullRequest proposal)
      onCreatePullRequest;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final quickLabel = switch (page.kind) {
      'actions' => 'Fix workflow',
      'pull_request' => 'Review PR',
      'issue' => 'Analyze issue',
      'file' => 'Explain file',
      _ => 'Inspect repo',
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Material(
          elevation: 12,
          color: cs.surface.withValues(alpha: .96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 19),
                    const SizedBox(width: 8),
                    const Text(
                      'Gradient',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        page.fullName ?? 'GitHub',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: onClose,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    onPressed: busy ? null : onQuickAction,
                    avatar: const Icon(Icons.bolt_rounded, size: 16),
                    label: Text(quickLabel),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: messages.isEmpty &&
                        changes.isEmpty &&
                        pullRequests.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            page.hasRepository
                                ? 'Ask about the GitHub page behind this panel. Gradient already knows which repo/page you are viewing.'
                                : 'Browse to a repository, PR, issue, file, or Actions page, then ask Gradient about it.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          for (final message in messages)
                            _MessageBubble(message: message),
                          for (final change in changes)
                            _ChangeCard(
                              change: change,
                              onApply: () => onApplyChange(change),
                            ),
                          for (final proposal in pullRequests)
                            _PullRequestCard(
                              proposal: proposal,
                              onCreate: () =>
                                  onCreatePullRequest(proposal),
                            ),
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text('Working on this page…'),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !busy,
                      onSubmitted: (_) {
                        if (!busy) onSend();
                      },
                      decoration: const InputDecoration(
                        hintText: 'Ask about this GitHub page…',
                        border: InputBorder.none,
                      ),
                    ),
                    Row(
                      children: [
                        FilterChip(
                          label: const Text('Web'),
                          selected: webEnabled,
                          onSelected:
                              busy ? null : (_) => onToggleWeb(),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Chip(
                            label: Text(
                              modelLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide.none,
                          ),
                        ),
                        const Spacer(),
                        IconButton.filled(
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
            ],
          ),
        ),
      ),
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
            constraints: const BoxConstraints(maxHeight: 320),
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
                  'GitHub is unchanged until you approve.',
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
            const SizedBox(height: 8),
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
            const SizedBox(height: 10),
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
