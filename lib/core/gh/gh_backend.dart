import 'dart:convert';

import '../github/github_models.dart';
import 'gh_command_runner.dart';

class GhRepository {
  const GhRepository({
    required this.fullName,
    required this.name,
    required this.description,
    required this.isPrivate,
    required this.defaultBranch,
    required this.updatedAt,
  });

  final String fullName;
  final String name;
  final String description;
  final bool isPrivate;
  final String defaultBranch;
  final String updatedAt;
}

class GhViewer {
  const GhViewer({
    required this.login,
    required this.name,
    required this.avatarUrl,
  });

  final String login;
  final String name;
  final String avatarUrl;
}

class GhIssue {
  const GhIssue({
    required this.number,
    required this.title,
    required this.state,
    required this.updatedAt,
    required this.author,
  });

  final int number;
  final String title;
  final String state;
  final String updatedAt;
  final String author;
}

class GhPullRequest {
  const GhPullRequest({
    required this.number,
    required this.title,
    required this.state,
    required this.isDraft,
    required this.updatedAt,
    required this.author,
    required this.headRefName,
    required this.baseRefName,
    required this.url,
  });

  final int number;
  final String title;
  final String state;
  final bool isDraft;
  final String updatedAt;
  final String author;
  final String headRefName;
  final String baseRefName;
  final String url;
}

class GhFile {
  const GhFile({
    required this.path,
    required this.sha,
    required this.content,
  });

  final String path;
  final String sha;
  final String content;
}

class GhBackend {
  GhBackend({required String token}) : _runner = GhCommandRunner(token: token);

  final GhCommandRunner _runner;

  Future<String> version() => _runner.version();

  Future<GhViewer> viewer() async {
    final result = await _runner.run(const ['api', 'user']);
    final json = jsonDecode(result.stdout) as Map<String, dynamic>;
    return GhViewer(
      login: json['login'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
    );
  }

  Future<List<GhRepository>> listRepositories() async {
    final result = await _runner.run(const [
      'repo',
      'list',
      '--limit',
      '100',
      '--json',
      'nameWithOwner,name,description,isPrivate,defaultBranchRef,updatedAt',
    ]);
    final raw = jsonDecode(result.stdout) as List<dynamic>;
    return raw.map((entry) {
      final json = entry as Map<String, dynamic>;
      final branch =
          json['defaultBranchRef'] as Map<String, dynamic>? ?? const {};
      return GhRepository(
        fullName: json['nameWithOwner'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        isPrivate: json['isPrivate'] as bool? ?? false,
        defaultBranch: branch['name'] as String? ?? 'main',
        updatedAt: json['updatedAt'] as String? ?? '',
      );
    }).where((repo) => repo.fullName.isNotEmpty).toList(growable: false);
  }

  Future<List<String>> listBranches(String fullName) async {
    final result = await _runner.run([
      'api',
      'repos/$fullName/branches?per_page=100',
      '--jq',
      '.[].name',
    ]);
    return result.stdout
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<GitHubEntry>> listContents(
    String fullName, {
    String path = '',
    required String ref,
  }) async {
    final endpoint = _contentsEndpoint(fullName, path, ref);
    final result = await _runner.run(['api', endpoint]);
    final decoded = jsonDecode(result.stdout);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(GitHubEntry.fromJson)
        .toList(growable: false);
  }

  Future<GhFile> readFile(
    String fullName,
    String path, {
    required String ref,
  }) async {
    final endpoint = _contentsEndpoint(fullName, path, ref);
    final result = await _runner.run(['api', endpoint]);
    final json = jsonDecode(result.stdout) as Map<String, dynamic>;
    final encoded =
        (json['content'] as String? ?? '').replaceAll('\n', '');

    return GhFile(
      path: path,
      sha: json['sha'] as String? ?? '',
      content: utf8.decode(base64.decode(encoded)),
    );
  }

  Future<List<GhIssue>> listIssues(String fullName) async {
    final result = await _runner.run([
      'issue',
      'list',
      '--repo',
      fullName,
      '--limit',
      '50',
      '--state',
      'all',
      '--json',
      'number,title,state,updatedAt,author',
    ]);
    final raw = jsonDecode(result.stdout) as List<dynamic>;
    return raw.map((entry) {
      final json = entry as Map<String, dynamic>;
      final author = json['author'] as Map<String, dynamic>? ?? const {};
      return GhIssue(
        number: (json['number'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        state: json['state'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
        author: author['login'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  Future<List<GhPullRequest>> listPullRequests(String fullName) async {
    final result = await _runner.run([
      'pr',
      'list',
      '--repo',
      fullName,
      '--limit',
      '50',
      '--state',
      'all',
      '--json',
      'number,title,state,isDraft,updatedAt,author,headRefName,baseRefName,url',
    ]);
    final raw = jsonDecode(result.stdout) as List<dynamic>;
    return raw.map((entry) {
      final json = entry as Map<String, dynamic>;
      final author = json['author'] as Map<String, dynamic>? ?? const {};
      return GhPullRequest(
        number: (json['number'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        state: json['state'] as String? ?? '',
        isDraft: json['isDraft'] as bool? ?? false,
        updatedAt: json['updatedAt'] as String? ?? '',
        author: author['login'] as String? ?? '',
        headRefName: json['headRefName'] as String? ?? '',
        baseRefName: json['baseRefName'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  Future<List<GitHubWorkflowRun>> listWorkflowRuns(
    String fullName, {
    int count = 30,
  }) async {
    final result = await _runner.run([
      'run',
      'list',
      '--repo',
      fullName,
      '--limit',
      '$count',
      '--json',
      'databaseId,name,status,conclusion,headBranch,url',
    ]);
    final raw = jsonDecode(result.stdout) as List<dynamic>;
    return raw.map((entry) {
      final json = entry as Map<String, dynamic>;
      return GitHubWorkflowRun(
        id: (json['databaseId'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? '',
        conclusion: json['conclusion'] as String? ?? '',
        branch: json['headBranch'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  Future<List<GitHubWorkflowJob>> listWorkflowJobs(
    String fullName,
    int runId,
  ) async {
    final result = await _runner.run([
      'run',
      'view',
      '$runId',
      '--repo',
      fullName,
      '--json',
      'jobs',
    ]);
    final json = jsonDecode(result.stdout) as Map<String, dynamic>;
    final jobs = json['jobs'] as List<dynamic>? ?? const [];
    return jobs.map((entry) {
      final job = entry as Map<String, dynamic>;
      return GitHubWorkflowJob(
        id: (job['databaseId'] as num?)?.toInt() ?? 0,
        name: job['name'] as String? ?? '',
        status: job['status'] as String? ?? '',
        conclusion: job['conclusion'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  Future<String> workflowJobLog(String fullName, int jobId) async {
    final result = await _runner.run([
      'api',
      '--allow-escape-sequences',
      'repos/$fullName/actions/jobs/$jobId/logs',
    ]);
    return _stripTerminalSequences(result.stdout);
  }

  Future<String> createBranch({
    required String fullName,
    required String branch,
    required String from,
  }) async {
    final source = await _runner.run([
      'api',
      'repos/$fullName/git/ref/heads/$from',
      '--jq',
      '.object.sha',
    ]);
    final sha = source.stdout.trim();
    if (sha.isEmpty) {
      throw const GhCommandException(-1, 'Could not resolve source branch SHA.');
    }

    await _runner.run([
      'api',
      '--method',
      'POST',
      'repos/$fullName/git/refs',
      '-f',
      'ref=refs/heads/$branch',
      '-f',
      'sha=$sha',
    ]);
    return branch;
  }

  Future<String> writeFile({
    required String fullName,
    required String path,
    required String content,
    required String message,
    required String branch,
    String? currentSha,
  }) async {
    final body = jsonEncode({
      'message': message,
      'content': base64.encode(utf8.encode(content)),
      'branch': branch,
      if (currentSha != null && currentSha.isNotEmpty) 'sha': currentSha,
    });

    final result = await _runner.run(
      [
        'api',
        '--method',
        'PUT',
        'repos/$fullName/contents/$path',
        '--input',
        '-',
      ],
      stdin: body,
    );
    final json = jsonDecode(result.stdout) as Map<String, dynamic>;
    final commit = json['commit'] as Map<String, dynamic>? ?? const {};
    return commit['sha'] as String? ?? '';
  }

  Future<String> createPullRequest({
    required String fullName,
    required String title,
    required String body,
    required String head,
    required String base,
  }) async {
    final result = await _runner.run([
      'pr',
      'create',
      '--repo',
      fullName,
      '--title',
      title,
      '--body',
      body,
      '--head',
      head,
      '--base',
      base,
    ]);
    return result.stdout.trim();
  }

  String _contentsEndpoint(String fullName, String path, String ref) {
    final safePath = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final suffix = safePath.isEmpty ? '' : '/$safePath';
    return 'repos/$fullName/contents$suffix?ref=${Uri.encodeQueryComponent(ref)}';
  }

  String _stripTerminalSequences(String input) {
    var value = input;

    // CSI sequences such as colors, cursor movement, and erase commands.
    value = value.replaceAll(
      RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'),
      '',
    );

    // OSC sequences, including hyperlinks and terminal title changes.
    value = value.replaceAll(
      RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)'),
      '',
    );

    // Keep newlines and tabs, but remove the remaining unsafe controls.
    value = value.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
      '',
    );

    return value.replaceAll('\r', '');
  }
}
