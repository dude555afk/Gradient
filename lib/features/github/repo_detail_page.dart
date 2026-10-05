import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/gh/gh_backend.dart';
import '../../core/github/github_models.dart';
import '../../core/settings/app_settings.dart';
import '../../core/security/protected_path.dart';
import '../../core/workspace/workspace_store.dart';
import '../agent/agent_sheet.dart';
import '../workspace/github_workspace_page.dart';

class RepoDetailPage extends StatefulWidget {
  const RepoDetailPage({
    super.key,
    required this.workspace,
  });

  final WorkspaceSelection workspace;

  @override
  State<RepoDetailPage> createState() => _RepoDetailPageState();
}

class _RepoDetailPageState extends State<RepoDetailPage> {
  final _settings = AppSettingsStore();

  late WorkspaceSelection _workspace;
  bool _loading = true;
  String? _error;

  List<GitHubEntry> _entries = const [];
  List<GhIssue> _issues = const [];
  List<GhPullRequest> _pullRequests = const [];
  List<GhCommit> _commits = const [];
  List<GitHubWorkflowRun> _runs = const [];

  @override
  void initState() {
    super.initState();
    _workspace = widget.workspace;
    _load();
  }

  Future<GhBackend> _backend() async {
    final token = await _settings.githubToken();
    return GhBackend(token: token);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final gh = await _backend();
      final results = await Future.wait<dynamic>([
        gh.listContents(
          _workspace.fullName,
          ref: _workspace.branch,
        ),
        gh.listIssues(_workspace.fullName),
        gh.listPullRequests(_workspace.fullName),
        gh.listCommits(
          _workspace.fullName,
          ref: _workspace.branch,
        ),
        gh.listWorkflowRuns(_workspace.fullName),
      ]);

      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<GitHubEntry>;
        _issues = results[1] as List<GhIssue>;
        _pullRequests = results[2] as List<GhPullRequest>;
        _commits = results[3] as List<GhCommit>;
        _runs = results[4] as List<GitHubWorkflowRun>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _chooseBranch() async {
    try {
      final gh = await _backend();
      final branches = await gh.listBranches(_workspace.fullName);
      if (!mounted) return;

      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Branches',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final branch in branches)
                ListTile(
                  leading: Icon(
                    branch == _workspace.branch
                        ? Icons.check_circle_rounded
                        : Icons.call_split_rounded,
                  ),
                  title: Text(branch),
                  onTap: () => Navigator.pop(context, branch),
                ),
            ],
          ),
        ),
      );

      if (selected == null || selected == _workspace.branch) return;
      final next = _workspace.copyWith(branch: selected);
      await WorkspaceStore().save(next);
      if (!mounted) return;
      setState(() => _workspace = next);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _openAgent([String contextText = '']) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AgentSheet(
        workspace: _workspace,
        contextText: contextText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _workspace.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17),
              ),
              InkWell(
                onTap: _chooseBranch,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.call_split_rounded, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      _workspace.branch,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const Icon(Icons.arrow_drop_down_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Search code',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RepoCodeSearchPage(
                      workspace: _workspace,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.manage_search_rounded),
            ),
            IconButton(
              tooltip: 'Open on GitHub',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GitHubWorkspacePage(
                      initialUrl: 'https://github.com/' + _workspace.fullName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.open_in_browser_rounded),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Code'),
              Tab(text: 'Issues'),
              Tab(text: 'Pull requests'),
              Tab(text: 'Commits'),
              Tab(text: 'Actions'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openAgent(
            'Native repository screen for ' +
                _workspace.fullName +
                ' on branch ' +
                _workspace.branch +
                '.',
          ),
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Gradient'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _RepoError(
                    message: _error!,
                    onRetry: _load,
                  )
                : TabBarView(
                    children: [
                      _CodeRoot(
                        workspace: _workspace,
                        entries: _entries,
                        settings: _settings,
                        onAgent: _openAgent,
                      ),
                      _IssuesList(
                        workspace: _workspace,
                        issues: _issues,
                      ),
                      _PullRequestsList(
                        workspace: _workspace,
                        pullRequests: _pullRequests,
                      ),
                      _CommitsList(
                        workspace: _workspace,
                        commits: _commits,
                        onAgent: _openAgent,
                      ),
                      _ActionsList(
                        workspace: _workspace,
                        runs: _runs,
                        settings: _settings,
                        onAgent: _openAgent,
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _RepoError extends StatelessWidget {
  const _RepoError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeRoot extends StatelessWidget {
  const _CodeRoot({
    required this.workspace,
    required this.entries,
    required this.settings,
    required this.onAgent,
  });

  final WorkspaceSelection workspace;
  final List<GitHubEntry> entries;
  final AppSettingsStore settings;
  final void Function(String contextText) onAgent;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No files found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final folder = entry.type == 'dir';
        return ListTile(
          leading: Icon(
            folder ? Icons.folder_rounded : Icons.description_outlined,
          ),
          title: Text(entry.name),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CodeBrowserPage(
                  workspace: workspace,
                  path: entry.path,
                  isDirectory: folder,
                  settings: settings,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class CodeBrowserPage extends StatefulWidget {
  const CodeBrowserPage({
    super.key,
    required this.workspace,
    required this.path,
    required this.isDirectory,
    required this.settings,
  });

  final WorkspaceSelection workspace;
  final String path;
  final bool isDirectory;
  final AppSettingsStore settings;

  @override
  State<CodeBrowserPage> createState() => _CodeBrowserPageState();
}

class _CodeBrowserPageState extends State<CodeBrowserPage> {
  bool _loading = true;
  String? _error;
  List<GitHubEntry> _entries = const [];
  GhFile? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await widget.settings.githubToken();
      final gh = GhBackend(token: token);

      if (widget.isDirectory) {
        final entries = await gh.listContents(
          widget.workspace.fullName,
          path: widget.path,
          ref: widget.workspace.branch,
        );
        if (!mounted) return;
        setState(() {
          _entries = entries;
          _loading = false;
        });
      } else {
        final file = await gh.readFile(
          widget.workspace.fullName,
          widget.path,
          ref: widget.workspace.branch,
        );
        if (!mounted) return;
        setState(() {
          _file = file;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _openAgent() {
    final file = _file;
    final protected = isProtectedRepositoryPath(widget.path);
    final extra = file == null
        ? ''
        : protected
            ? '\nFile content withheld because this path is protected.'
            : '\nVisible file content:\n' +
                (file.content.length > 12000
                    ? file.content.substring(0, 12000)
                    : file.content);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AgentSheet(
        workspace: widget.workspace,
        contextText: 'Native code screen. Path: ' + widget.path + extra,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Ask Gradient',
            onPressed: _openAgent,
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _RepoError(
                  message: _error!,
                  onRetry: _load,
                )
              : widget.isDirectory
                  ? ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final folder = entry.type == 'dir';
                        return ListTile(
                          leading: Icon(
                            folder
                                ? Icons.folder_rounded
                                : Icons.description_outlined,
                          ),
                          title: Text(entry.name),
                          trailing:
                              const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CodeBrowserPage(
                                  workspace: widget.workspace,
                                  path: entry.path,
                                  isDirectory: folder,
                                  settings: widget.settings,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                      child: SelectableText(
                        _file?.content ?? '',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
    );
  }
}

class _IssuesList extends StatelessWidget {
  const _IssuesList({
    required this.workspace,
    required this.issues,
  });

  final WorkspaceSelection workspace;
  final List<GhIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const Center(child: Text('No issues'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: issues.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final issue = issues[index];
        return ListTile(
          leading: Icon(
            issue.state.toUpperCase() == 'OPEN'
                ? Icons.adjust_rounded
                : Icons.check_circle_outline_rounded,
          ),
          title: Text(issue.title),
          subtitle: Text(
            '#' +
                issue.number.toString() +
                (issue.author.isEmpty ? '' : ' • ' + issue.author),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => IssueDetailPage(
                  workspace: workspace,
                  number: issue.number,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PullRequestsList extends StatelessWidget {
  const _PullRequestsList({
    required this.workspace,
    required this.pullRequests,
  });

  final WorkspaceSelection workspace;
  final List<GhPullRequest> pullRequests;

  @override
  Widget build(BuildContext context) {
    if (pullRequests.isEmpty) {
      return const Center(child: Text('No pull requests'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: pullRequests.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final pr = pullRequests[index];
        return ListTile(
          leading: Icon(
            pr.isDraft ? Icons.edit_note_rounded : Icons.merge_rounded,
          ),
          title: Text(pr.title),
          subtitle: Text(
            '#' +
                pr.number.toString() +
                ' • ' +
                pr.headRefName +
                ' → ' +
                pr.baseRefName,
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PullRequestDetailPage(
                  workspace: workspace,
                  number: pr.number,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class RepoCodeSearchPage extends StatefulWidget {
  const RepoCodeSearchPage({
    super.key,
    required this.workspace,
  });

  final WorkspaceSelection workspace;

  @override
  State<RepoCodeSearchPage> createState() => _RepoCodeSearchPageState();
}

class _RepoCodeSearchPageState extends State<RepoCodeSearchPage> {
  final _query = TextEditingController();
  final _settings = AppSettingsStore();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _settings.githubToken();
      final results =
          await GhBackend(token: token).searchCode(
        widget.workspace.fullName,
        query,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search code')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              controller: _query,
              hintText: 'Search this repository',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                IconButton(
                  onPressed: _loading ? null : _search,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_rounded),
                ),
              ],
              onSubmitted: (_) => _search(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _results.isEmpty && !_loading
                ? const Center(
                    child: Text(
                      'Search file names, symbols, strings, or code.',
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      final path = result['path']?.toString() ?? '';
                      return ListTile(
                        leading:
                            const Icon(Icons.manage_search_rounded),
                        title: Text(path),
                        subtitle: Text(
                          result['repository']?.toString() ??
                              widget.workspace.fullName,
                        ),
                        trailing:
                            const Icon(Icons.chevron_right_rounded),
                        onTap: path.isEmpty
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => CodeBrowserPage(
                                      workspace: WorkspaceSelection(
                                        fullName:
                                            widget.workspace.fullName,
                                        defaultBranch:
                                            widget.workspace.defaultBranch,
                                        branch:
                                            widget.workspace.defaultBranch,
                                      ),
                                      path: path,
                                      isDirectory: false,
                                      settings: _settings,
                                    ),
                                  ),
                                );
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class IssueDetailPage extends StatefulWidget {
  const IssueDetailPage({
    super.key,
    required this.workspace,
    required this.number,
  });

  final WorkspaceSelection workspace;
  final int number;

  @override
  State<IssueDetailPage> createState() => _IssueDetailPageState();
}

class _IssueDetailPageState extends State<IssueDetailPage> {
  final _settings = AppSettingsStore();
  GhIssueDetail? _issue;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _settings.githubToken();
      final issue = await GhBackend(token: token).issueDetail(
        widget.workspace.fullName,
        widget.number,
      );
      if (!mounted) return;
      setState(() {
        _issue = issue;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _askGradient() {
    final issue = _issue;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AgentSheet(
        workspace: widget.workspace,
        contextText: issue == null
            ? 'Native issue #${widget.number}.'
            : 'Native issue #${issue.number}: ${issue.title}. '
                'State: ${issue.state}. Author: ${issue.author}.\n'
                'Body:\n${issue.body.length > 6000 ? issue.body.substring(0, 6000) : issue.body}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    return Scaffold(
      appBar: AppBar(
        title: Text('Issue #${widget.number}'),
        actions: [
          IconButton(
            tooltip: 'Ask Gradient',
            onPressed: _askGradient,
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _RepoError(message: _error!, onRetry: _load)
              : issue == null
                  ? const Center(child: Text('Issue unavailable'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      children: [
                        Text(
                          issue.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Chip(
                              avatar: Icon(
                                issue.state.toLowerCase() == 'open'
                                    ? Icons.adjust_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 16,
                              ),
                              label: Text(issue.state),
                            ),
                            if (issue.author.isNotEmpty)
                              Chip(label: Text('@${issue.author}')),
                            for (final label in issue.labels)
                              Chip(label: Text(label)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        MarkdownBody(
                          data: issue.body.trim().isEmpty
                              ? '_No description provided._'
                              : issue.body,
                          selectable: true,
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Comments (${issue.comments.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final comment in issue.comments)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '@${comment.author}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  MarkdownBody(
                                    data: comment.body,
                                    selectable: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class PullRequestDetailPage extends StatefulWidget {
  const PullRequestDetailPage({
    super.key,
    required this.workspace,
    required this.number,
  });

  final WorkspaceSelection workspace;
  final int number;

  @override
  State<PullRequestDetailPage> createState() =>
      _PullRequestDetailPageState();
}

class _PullRequestDetailPageState extends State<PullRequestDetailPage> {
  final _settings = AppSettingsStore();
  GhPullRequestDetail? _pullRequest;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _settings.githubToken();
      final pr = await GhBackend(token: token).pullRequestDetail(
        widget.workspace.fullName,
        widget.number,
      );
      if (!mounted) return;
      setState(() {
        _pullRequest = pr;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _askGradient() {
    final pr = _pullRequest;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AgentSheet(
        workspace: widget.workspace,
        contextText: pr == null
            ? 'Native pull request #${widget.number}.'
            : 'Native pull request #${pr.number}: ${pr.title}. '
                '${pr.headRefName} -> ${pr.baseRefName}. '
                'State: ${pr.state}; mergeable: ${pr.mergeable}; '
                '+${pr.additions}/-${pr.deletions}; '
                '${pr.changedFiles.length} changed files.\n'
                'Body:\n${pr.body.length > 6000 ? pr.body.substring(0, 6000) : pr.body}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pr = _pullRequest;
    return Scaffold(
      appBar: AppBar(
        title: Text('PR #${widget.number}'),
        actions: [
          IconButton(
            tooltip: 'Ask Gradient',
            onPressed: _askGradient,
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _RepoError(message: _error!, onRetry: _load)
              : pr == null
                  ? const Center(child: Text('Pull request unavailable'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      children: [
                        Text(
                          pr.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Chip(
                              avatar: Icon(
                                pr.isDraft
                                    ? Icons.edit_note_rounded
                                    : Icons.merge_rounded,
                                size: 16,
                              ),
                              label: Text(
                                pr.isDraft ? 'Draft' : pr.state,
                              ),
                            ),
                            if (pr.author.isNotEmpty)
                              Chip(label: Text('@${pr.author}')),
                            Chip(
                              label: Text(
                                '${pr.headRefName} → ${pr.baseRefName}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                '+${pr.additions} / -${pr.deletions}',
                              ),
                            ),
                            if (pr.mergeable.isNotEmpty)
                              Chip(label: Text(pr.mergeable)),
                            for (final label in pr.labels)
                              Chip(label: Text(label)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        MarkdownBody(
                          data: pr.body.trim().isEmpty
                              ? '_No description provided._'
                              : pr.body,
                          selectable: true,
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Changed files (${pr.changedFiles.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final file in pr.changedFiles)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                const Icon(Icons.description_outlined),
                            title: Text(file.path),
                            subtitle: Text(file.status),
                            trailing: Text(
                              '+${file.additions}  -${file.deletions}',
                            ),
                          ),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Comments (${pr.comments.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final comment in pr.comments)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '@${comment.author}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  MarkdownBody(
                                    data: comment.body,
                                    selectable: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _CommitsList extends StatelessWidget {
  const _CommitsList({
    required this.workspace,
    required this.commits,
    required this.onAgent,
  });

  final WorkspaceSelection workspace;
  final List<GhCommit> commits;
  final void Function(String contextText) onAgent;

  @override
  Widget build(BuildContext context) {
    if (commits.isEmpty) {
      return const Center(child: Text('No commits found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: commits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final commit = commits[index];
        final shortSha =
            commit.sha.length > 8 ? commit.sha.substring(0, 8) : commit.sha;

        return ListTile(
          leading: const Icon(Icons.commit_rounded),
          title: Text(
            commit.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${commit.author.isEmpty ? 'unknown' : commit.author} • $shortSha',
          ),
          trailing: IconButton(
            tooltip: 'Ask Gradient about this commit',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => onAgent(
              'Commit $shortSha in ${workspace.fullName} on '
              '${workspace.branch}: ${commit.message}. '
              'Inspect this commit and explain or review it.',
            ),
          ),
        );
      },
    );
  }
}

class _ActionsList extends StatelessWidget {
  const _ActionsList({
    required this.workspace,
    required this.runs,
    required this.settings,
    required this.onAgent,
  });

  final WorkspaceSelection workspace;
  final List<GitHubWorkflowRun> runs;
  final AppSettingsStore settings;
  final void Function(String contextText) onAgent;

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const Center(child: Text('No workflow runs'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: runs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final run = runs[index];
        final failed = run.conclusion.toLowerCase() == 'failure';

        return ListTile(
          leading: Icon(
            failed
                ? Icons.cancel_outlined
                : run.status.toLowerCase() == 'completed'
                    ? Icons.check_circle_outline_rounded
                    : Icons.pending_outlined,
          ),
          title: Text(run.name),
          subtitle: Text(
            run.branch +
                ' • ' +
                (run.conclusion.isEmpty ? run.status : run.conclusion),
          ),
          trailing: failed
              ? IconButton(
                  tooltip: 'Fix with Gradient',
                  onPressed: () => onAgent(
                    'Workflow run ' +
                        run.id.toString() +
                        ' is failing in ' +
                        workspace.fullName +
                        '. Inspect its jobs and logs and propose a safe fix.',
                  ),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                )
              : const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WorkflowRunPage(
                  workspace: workspace,
                  run: run,
                  settings: settings,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class WorkflowRunPage extends StatefulWidget {
  const WorkflowRunPage({
    super.key,
    required this.workspace,
    required this.run,
    required this.settings,
  });

  final WorkspaceSelection workspace;
  final GitHubWorkflowRun run;
  final AppSettingsStore settings;

  @override
  State<WorkflowRunPage> createState() => _WorkflowRunPageState();
}

class _WorkflowRunPageState extends State<WorkflowRunPage> {
  bool _loading = true;
  bool _acting = false;
  String? _error;
  List<GitHubWorkflowJob> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<GhBackend> _backend() async {
    final token = await widget.settings.githubToken();
    if (token.isEmpty) {
      throw StateError('Connect GitHub before controlling workflows.');
    }
    return GhBackend(token: token);
  }

  Future<void> _load() async {
    try {
      final gh = await _backend();
      final jobs = await gh.listWorkflowJobs(
        widget.workspace.fullName,
        widget.run.id,
      );
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _rerun({required bool failedOnly}) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final gh = await _backend();
      await gh.rerunWorkflow(
        widget.workspace.fullName,
        widget.run.id,
        failedOnly: failedOnly,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedOnly
                ? 'Rerunning failed jobs.'
                : 'Rerunning the workflow.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _cancel() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final gh = await _backend();
      await gh.cancelWorkflow(
        widget.workspace.fullName,
        widget.run.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workflow cancellation requested.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _openLog(GitHubWorkflowJob job) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return FutureBuilder<String>(
          future: widget.settings.githubToken().then(
                (token) => GhBackend(token: token).workflowJobLog(
                  widget.workspace.fullName,
                  job.id,
                ),
              ),
          builder: (context, snapshot) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .84,
                child: snapshot.connectionState != ConnectionState.done
                    ? const Center(child: CircularProgressIndicator())
                    : snapshot.hasError
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                snapshot.error.toString(),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(14),
                            child: SelectableText(
                              snapshot.data ?? '',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                              ),
                            ),
                          ),
              ),
            );
          },
        );
      },
    );
  }

  void _askGradient() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AgentSheet(
        workspace: widget.workspace,
        contextText: 'Native Actions run screen. Run id: ' +
            widget.run.id.toString() +
            ', workflow: ' +
            widget.run.name +
            ', status: ' +
            widget.run.status +
            ', conclusion: ' +
            widget.run.conclusion +
            '.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completed = widget.run.status.toLowerCase() == 'completed';
    final failed = widget.run.conclusion.toLowerCase() == 'failure';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.run.name),
        actions: [
          IconButton(
            tooltip: 'Ask Gradient',
            onPressed: _askGradient,
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _RepoError(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (completed)
                              FilledButton.tonalIcon(
                                onPressed: _acting
                                    ? null
                                    : () => _rerun(failedOnly: false),
                                icon: const Icon(Icons.replay_rounded),
                                label: const Text('Rerun'),
                              ),
                            if (completed && failed) ...[
                              const SizedBox(width: 8),
                              FilledButton.tonalIcon(
                                onPressed: _acting
                                    ? null
                                    : () => _rerun(failedOnly: true),
                                icon:
                                    const Icon(Icons.restart_alt_rounded),
                                label: const Text('Rerun failed'),
                              ),
                            ],
                            if (!completed)
                              FilledButton.tonalIcon(
                                onPressed: _acting ? null : _cancel,
                                icon: const Icon(Icons.stop_circle_outlined),
                                label: const Text('Cancel run'),
                              ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _acting ? null : _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Refresh jobs'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _jobs.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final job = _jobs[index];
                          return ListTile(
                            leading: Icon(
                              job.conclusion.toLowerCase() == 'failure'
                                  ? Icons.cancel_outlined
                                  : job.status.toLowerCase() == 'completed'
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.pending_outlined,
                            ),
                            title: Text(job.name),
                            subtitle: Text(
                              job.conclusion.isEmpty
                                  ? job.status
                                  : job.conclusion,
                            ),
                            trailing:
                                const Icon(Icons.article_outlined),
                            onTap: () => _openLog(job),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
