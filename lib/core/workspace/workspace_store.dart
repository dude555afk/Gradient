import 'package:shared_preferences/shared_preferences.dart';

class WorkspaceSelection {
  const WorkspaceSelection({
    required this.fullName,
    required this.defaultBranch,
    required this.branch,
  });

  final String fullName;
  final String defaultBranch;
  final String branch;

  WorkspaceSelection copyWith({String? branch}) {
    return WorkspaceSelection(
      fullName: fullName,
      defaultBranch: defaultBranch,
      branch: branch ?? this.branch,
    );
  }
}

class WorkspaceStore {
  Future<WorkspaceSelection?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString('workspace_repo') ?? '';
    if (fullName.isEmpty) return null;

    final defaultBranch = prefs.getString('workspace_default_branch') ?? 'main';
    final branch = prefs.getString('workspace_branch') ?? defaultBranch;
    return WorkspaceSelection(
      fullName: fullName,
      defaultBranch: defaultBranch,
      branch: branch,
    );
  }

  Future<void> save(WorkspaceSelection selection) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('workspace_repo', selection.fullName),
      prefs.setString('workspace_default_branch', selection.defaultBranch),
      prefs.setString('workspace_branch', selection.branch),
    ]);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('workspace_repo'),
      prefs.remove('workspace_default_branch'),
      prefs.remove('workspace_branch'),
    ]);
  }
}
