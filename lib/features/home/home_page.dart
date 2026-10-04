import 'package:flutter/material.dart';

import '../../core/gh/gh_backend.dart';
import '../../core/settings/app_settings.dart';
import '../../core/workspace/workspace_store.dart';
import '../agent/agent_sheet.dart';
import '../github/repo_detail_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _settings = AppSettingsStore();
  final _workspaceStore = WorkspaceStore();
  final _search = TextEditingController();

  GhViewer? _viewer;
  List<GhRepository> _repos = const [];
  WorkspaceSelection? _lastWorkspace;
  String _ghVersion = '';
  String? _error;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refreshSearch);
    _load();
  }

  void _refreshSearch() => setState(() {});

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final token = await _settings.githubToken();
    final workspace = await _workspaceStore.load();

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _lastWorkspace = workspace;
        _loading = false;
        _error = 'Connect GitHub to load your repositories.';
      });
      return;
    }

    final gh = GhBackend(token: token);
    try {
      final results = await Future.wait<dynamic>([
        gh.version(),
        gh.viewer(),
        gh.listRepositories(),
      ]);

      if (!mounted) return;
      setState(() {
        _ghVersion = results[0] as String;
        _viewer = results[1] as GhViewer;
        _repos = results[2] as List<GhRepository>;
        _lastWorkspace = workspace;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastWorkspace = workspace;
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsPage(),
      ),
    );
    await _load();
  }

  Future<void> _openRepo(GhRepository repo) async {
    final workspace = WorkspaceSelection(
      fullName: repo.fullName,
      defaultBranch: repo.defaultBranch,
      branch: repo.defaultBranch,
    );
    await _workspaceStore.save(workspace);

    if (!mounted) return;
    setState(() => _lastWorkspace = workspace);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RepoDetailPage(workspace: workspace),
      ),
    );
  }

  void _openAgent() {
    final workspace = _lastWorkspace;
    if (workspace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open a repository first so Gradient has context.'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AgentSheet(
        workspace: workspace,
        contextText: 'Gradient native GitHub home. Last active repository: ' +
            workspace.fullName +
            ', branch: ' +
            workspace.branch +
            '.',
      ),
    );
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleRepos = _filteredRepos();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gradient_rounded),
            SizedBox(width: 8),
            Text('Gradient'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAgent,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('Gradient'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          setState(() => _tab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Repositories',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _SetupState(
                  error: _error!,
                  onSettings: _openSettings,
                  onRetry: _load,
                )
              : _tab == 0
                  ? _HomeFeed(
                      viewer: _viewer!,
                      ghVersion: _ghVersion,
                      repos: _repos.take(8).toList(growable: false),
                      lastWorkspace: _lastWorkspace,
                      onRepo: _openRepo,
                    )
                  : _ReposView(
                      search: _search,
                      repos: visibleRepos,
                      onRepo: _openRepo,
                    ),
    );
  }

  List<GhRepository> _filteredRepos() {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _repos;

    return _repos
        .where(
          (repo) =>
              repo.fullName.toLowerCase().contains(query) ||
              repo.description.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }
}

class _SetupState extends StatelessWidget {
  const _SetupState({
    required this.error,
    required this.onSettings,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.code_rounded, size: 52),
            const SizedBox(height: 16),
            const Text(
              'GitHub CLI backend',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onSettings,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Connect GitHub'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeFeed extends StatelessWidget {
  const _HomeFeed({
    required this.viewer,
    required this.ghVersion,
    required this.repos,
    required this.lastWorkspace,
    required this.onRepo,
  });

  final GhViewer viewer;
  final String ghVersion;
  final List<GhRepository> repos;
  final WorkspaceSelection? lastWorkspace;
  final Future<void> Function(GhRepository repo) onRepo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: viewer.avatarUrl.isEmpty
                    ? null
                    : NetworkImage(viewer.avatarUrl),
                child: viewer.avatarUrl.isEmpty
                    ? const Icon(Icons.person_rounded)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      viewer.name.isEmpty ? viewer.login : viewer.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('@' + viewer.login),
                  ],
                ),
              ),
              Chip(
                avatar: const Icon(Icons.terminal_rounded, size: 16),
                label: Text(
                  ghVersion.isEmpty
                      ? 'gh'
                      : ghVersion.split('\n').first.replaceFirst(
                            'gh version ',
                            'gh ',
                          ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (lastWorkspace != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Continue'),
                subtitle: Text(
                  lastWorkspace!.fullName + ' • ' + lastWorkspace!.branch,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Recently updated',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final repo in repos)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  repo.isPrivate
                      ? Icons.lock_outline_rounded
                      : Icons.public_rounded,
                ),
                title: Text(repo.fullName),
                subtitle: Text(
                  repo.description.isEmpty
                      ? repo.defaultBranch
                      : repo.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant,
                ),
                onTap: () => onRepo(repo),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReposView extends StatelessWidget {
  const _ReposView({
    required this.search,
    required this.repos,
    required this.onRepo,
  });

  final TextEditingController search;
  final List<GhRepository> repos;
  final Future<void> Function(GhRepository repo) onRepo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SearchBar(
            controller: search,
            hintText: 'Search repositories',
            leading: const Icon(Icons.search_rounded),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 110),
            itemCount: repos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final repo = repos[index];
              return ListTile(
                leading: Icon(
                  repo.isPrivate
                      ? Icons.lock_outline_rounded
                      : Icons.public_rounded,
                ),
                title: Text(repo.fullName),
                subtitle: Text(
                  repo.description.isEmpty
                      ? repo.defaultBranch
                      : repo.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onRepo(repo),
              );
            },
          ),
        ),
      ],
    );
  }
}
