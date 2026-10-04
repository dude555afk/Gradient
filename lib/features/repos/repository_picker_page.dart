import 'package:flutter/material.dart';

import '../../core/github/github_models.dart';
import '../../core/github/github_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/workspace/workspace_store.dart';
import '../settings/settings_page.dart';

class RepositoryPickerPage extends StatefulWidget {
  const RepositoryPickerPage({super.key});

  @override
  State<RepositoryPickerPage> createState() => _RepositoryPickerPageState();
}

class _RepositoryPickerPageState extends State<RepositoryPickerPage> {
  final _settings = AppSettingsStore();
  final _workspace = WorkspaceStore();
  final _search = TextEditingController();

  List<GitHubRepository> _repos = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  Future<void> _load() async {
    final token = await _settings.githubToken();
    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Connect GitHub in Settings first.';
      });
      return;
    }

    final github = GitHubService(token: token);
    try {
      final repos = await github.listRepositories();
      if (!mounted) return;
      setState(() {
        _repos = repos;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    } finally {
      github.dispose();
    }
  }

  Future<void> _pick(GitHubRepository repo) async {
    final token = await _settings.githubToken();
    if (token.isEmpty || !mounted) return;

    final github = GitHubService(token: token);
    try {
      final branches = await github.listBranches(repo.fullName);
      if (!mounted) return;

      final branch = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(repo.fullName),
                subtitle: const Text('Choose active branch'),
              ),
              for (final branch in branches)
                ListTile(
                  leading: Icon(
                    branch == repo.defaultBranch
                        ? Icons.star_rounded
                        : Icons.call_split_rounded,
                  ),
                  title: Text(branch),
                  onTap: () => Navigator.pop(context, branch),
                ),
            ],
          ),
        ),
      );

      if (branch == null) return;

      final selection = WorkspaceSelection(
        fullName: repo.fullName,
        defaultBranch: repo.defaultBranch,
        branch: branch,
      );
      await _workspace.save(selection);

      if (!mounted) return;
      Navigator.pop(context, selection);
    } finally {
      github.dispose();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? _repos
        : _repos
            .where(
              (repo) =>
                  repo.fullName.toLowerCase().contains(q) ||
                  repo.description.toLowerCase().contains(q),
            )
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Repositories')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(
                  message: _error!,
                  onSettings: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsPage(),
                      ),
                    );
                  },
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SearchBar(
                        controller: _search,
                        hintText: 'Search repositories',
                        leading: const Icon(Icons.search_rounded),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final repo = visible[index];
                          return ListTile(
                            leading: Icon(
                              repo.private
                                  ? Icons.lock_outline_rounded
                                  : Icons.public_rounded,
                            ),
                            title: Text(repo.fullName),
                            subtitle: repo.description.isEmpty
                                ? Text(repo.defaultBranch)
                                : Text(
                                    repo.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _pick(repo),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onSettings,
  });

  final String message;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_rounded, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}
