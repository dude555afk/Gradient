import 'package:flutter/material.dart';

import '../../core/gh/gh_backend.dart';
import '../../core/github/github_models.dart';
import '../../core/settings/app_settings.dart';
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
        gh.listWorkflowRuns(_workspace.fullName),
      ]);

      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<GitHubEntry>;
        _issues = results[1] as List<GhIssue>;
        _pullRequests = results[2] as List<GhPullRequest>;
        _runs = results[3] as List<GitHubWorkflowRun>;
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
      length: 4,
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
    final extra = file == null
        ? ''
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
                builder: (_) => GitHubWorkspacePage(
                  initialUrl: 'https://github.com/' +
                      workspace.fullName +
                      '/issues/' +
                      issue.number.toString(),
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
                builder: (_) => GitHubWorkspacePage(
                  initialUrl: pr.url.isNotEmpty
                      ? pr.url
                      : 'https://github.com/' +
                          workspace.fullName +
                          '/pull/' +
                          pr.number.toString(),
                ),
              ),
            );
          },
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
  String? _error;
  List<GitHubWorkflowJob> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await widget.settings.githubToken();
      final gh = GhBackend(token: token);
      final jobs = await gh.listWorkflowJobs(
        widget.workspace.fullName,
        widget.run.id,
      );
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
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
              : ListView.separated(
                  itemCount: _jobs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
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
                      trailing: const Icon(Icons.article_outlined),
                      onTap: () => _openLog(job),
                    );
                  },
                ),
    );
  }
}
