import 'dart:convert';

import '../github/github_models.dart';
import 'gh_command_runner.dart';

class GhNotification {
  const GhNotification({
    required this.id,
    required this.repository,
    required this.defaultBranch,
    required this.title,
    required this.type,
    required this.reason,
    required this.unread,
    required this.updatedAt,
    required this.subjectUrl,
  });

  final String id;
  final String repository;
  final String defaultBranch;
  final String title;
  final String type;
  final String reason;
  final bool unread;
  final String updatedAt;
  final String subjectUrl;
}

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


class GhComment {
  const GhComment({
    required this.author,
    required this.body,
    required this.createdAt,
  });

  final String author;
  final String body;
  final String createdAt;
}

class GhIssueDetail {
  const GhIssueDetail({
    required this.number,
    required this.title,
    required this.state,
    required this.body,
    required this.author,
    required this.labels,
    required this.comments,
    required this.url,
  });

  final int number;
  final String title;
  final String state;
  final String body;
  final String author;
  final List<String> labels;
  final List<GhComment> comments;
  final String url;
}

class GhChangedFile {
  const GhChangedFile({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
  });

  final String path;
  final String status;
  final int additions;
  final int deletions;
}

class GhPullRequestDetail {
  const GhPullRequestDetail({
    required this.number,
    required this.title,
    required this.state,
    required this.body,
    required this.author,
    required this.labels,
    required this.comments,
    required this.url,
    required this.headRefName,
    required this.baseRefName,
    required this.additions,
    required this.deletions,
    required this.changedFiles,
    required this.mergeable,
    required this.isDraft,
  });

  final int number;
  final String title;
  final String state;
  final String body;
  final String author;
  final List<String> labels;
  final List<GhComment> comments;
  final String url;
  final String headRefName;
  final String baseRefName;
  final int additions;
  final int deletions;
  final List<GhChangedFile> changedFiles;
  final String mergeable;
  final bool isDraft;
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

  Future<List<GhNotification>> listNotifications({
    bool all = false,
    int limit = 50,
  }) async {
    final result = await _runner.run([
      'api',
      'notifications?all=${all ? 'true' : 'false'}&per_page=$limit',
    ]);
    final raw = jsonDecode(result.stdout) as List<dynamic>;

    return raw.whereType<Map>().map((entry) {
      final json = Map<String, dynamic>.from(entry);
      final repository =
          json['repository'] as Map<String, dynamic>? ?? const {};
      final subject =
          json['subject'] as Map<String, dynamic>? ?? const {};

      return GhNotification(
        id: json['id']?.toString() ?? '',
        repository: repository['full_name']?.toString() ?? '',
        defaultBranch:
            repository['default_branch']?.toString() ?? 'main',
        title: subject['title']?.toString() ?? '',
        type: subject['type']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        unread: json['unread'] as bool? ?? false,
        updatedAt: json['updated_at']?.toString() ?? '',
        subjectUrl: subject['url']?.toString() ?? '',
      );
    }).where((e) => e.id.isNotEmpty).toList(growable: false);
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

  Future<GhIssueDetail> issueDetail(
    String fullName,
    int number,
  ) async {
    final issueResult = await _runner.run([
      'api',
      'repos/$fullName/issues/$number',
    ]);
    final issue = jsonDecode(issueResult.stdout) as Map<String, dynamic>;

    final commentsResult = await _runner.run([
      'api',
      'repos/$fullName/issues/$number/comments?per_page=100',
    ]);
    final commentsRaw = jsonDecode(commentsResult.stdout) as List<dynamic>;

    final user = issue['user'] as Map<String, dynamic>? ?? const {};
    final labelsRaw = issue['labels'] as List<dynamic>? ?? const [];

    return GhIssueDetail(
      number: (issue['number'] as num?)?.toInt() ?? number,
      title: issue['title']?.toString() ?? '',
      state: issue['state']?.toString() ?? '',
      body: issue['body']?.toString() ?? '',
      author: user['login']?.toString() ?? '',
      labels: labelsRaw
          .whereType<Map>()
          .map((e) => e['name']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
      comments: commentsRaw.whereType<Map>().map((raw) {
        final comment = Map<String, dynamic>.from(raw);
        final author =
            comment['user'] as Map<String, dynamic>? ?? const {};
        return GhComment(
          author: author['login']?.toString() ?? '',
          body: comment['body']?.toString() ?? '',
          createdAt: comment['created_at']?.toString() ?? '',
        );
      }).toList(growable: false),
      url: issue['html_url']?.toString() ?? '',
    );
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

  Future<GhPullRequestDetail> pullRequestDetail(
    String fullName,
    int number,
  ) async {
    final prResult = await _runner.run([
      'api',
      'repos/$fullName/pulls/$number',
    ]);
    final pr = jsonDecode(prResult.stdout) as Map<String, dynamic>;

    final commentsResult = await _runner.run([
      'api',
      'repos/$fullName/issues/$number/comments?per_page=100',
    ]);
    final commentsRaw = jsonDecode(commentsResult.stdout) as List<dynamic>;

    final filesResult = await _runner.run([
      'api',
      'repos/$fullName/pulls/$number/files?per_page=100',
    ]);
    final filesRaw = jsonDecode(filesResult.stdout) as List<dynamic>;

    final user = pr['user'] as Map<String, dynamic>? ?? const {};
    final head = pr['head'] as Map<String, dynamic>? ?? const {};
    final base = pr['base'] as Map<String, dynamic>? ?? const {};
    final labelsRaw = pr['labels'] as List<dynamic>? ?? const [];

    return GhPullRequestDetail(
      number: (pr['number'] as num?)?.toInt() ?? number,
      title: pr['title']?.toString() ?? '',
      state: pr['state']?.toString() ?? '',
      body: pr['body']?.toString() ?? '',
      author: user['login']?.toString() ?? '',
      labels: labelsRaw
          .whereType<Map>()
          .map((e) => e['name']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
      comments: commentsRaw.whereType<Map>().map((raw) {
        final comment = Map<String, dynamic>.from(raw);
        final author =
            comment['user'] as Map<String, dynamic>? ?? const {};
        return GhComment(
          author: author['login']?.toString() ?? '',
          body: comment['body']?.toString() ?? '',
          createdAt: comment['created_at']?.toString() ?? '',
        );
      }).toList(growable: false),
      url: pr['html_url']?.toString() ?? '',
      headRefName: head['ref']?.toString() ?? '',
      baseRefName: base['ref']?.toString() ?? '',
      additions: (pr['additions'] as num?)?.toInt() ?? 0,
      deletions: (pr['deletions'] as num?)?.toInt() ?? 0,
      changedFiles: filesRaw.whereType<Map>().map((raw) {
        final file = Map<String, dynamic>.from(raw);
        return GhChangedFile(
          path: file['filename']?.toString() ?? '',
          status: file['status']?.toString() ?? '',
          additions: (file['additions'] as num?)?.toInt() ?? 0,
          deletions: (file['deletions'] as num?)?.toInt() ?? 0,
        );
      }).where((e) => e.path.isNotEmpty).toList(growable: false),
      mergeable: pr['mergeable_state']?.toString() ?? '',
      isDraft: pr['draft'] as bool? ?? false,
    );
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


  Future<List<String>> repositoryMap(
    String fullName, {
    required String ref,
    int maxEntries = 1600,
  }) async {
    final safeRef = Uri.encodeComponent(ref);
    final result = await _runner.run([
      'api',
      'repos/$fullName/git/trees/$safeRef?recursive=1',
    ]);
    final json = jsonDecode(result.stdout) as Map<String, dynamic>;
    final tree = json['tree'] as List<dynamic>? ?? const [];

    final paths = <String>[];
    for (final raw in tree) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final path = entry['path']?.toString() ?? '';
      final type = entry['type']?.toString() ?? '';
      if (path.isEmpty) continue;
      paths.add(type == 'tree' ? '$path/' : path);
      if (paths.length >= maxEntries) break;
    }
    return paths;
  }

  Future<List<Map<String, dynamic>>> searchCode(
    String fullName,
    String query, {
    int limit = 30,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];

    final result = await _runner.run([
      'api',
      '--method',
      'GET',
      'search/code',
      '-f',
      'q=$normalized repo:$fullName',
      '-f',
      'per_page=$limit',
    ]);

    final json = jsonDecode(result.stdout) as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>? ?? const [];

    return items.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final repository =
          item['repository'] as Map<String, dynamic>? ?? const {};
      return <String, dynamic>{
        'path': item['path']?.toString() ?? '',
        'url': item['html_url']?.toString() ?? '',
        'repository': repository['full_name']?.toString() ?? fullName,
      };
    }).toList(growable: false);
  }

  Future<void> rerunWorkflow(
    String fullName,
    int runId, {
    bool failedOnly = false,
  }) async {
    await _runner.run([
      'run',
      'rerun',
      '$runId',
      '--repo',
      fullName,
      if (failedOnly) '--failed',
    ]);
  }

  Future<void> cancelWorkflow(String fullName, int runId) async {
    await _runner.run([
      'run',
      'cancel',
      '$runId',
      '--repo',
      fullName,
    ]);
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

  Future<String> writeFilesBatch({
    required String fullName,
    required String branch,
    required Map<String, String> files,
    required String message,
  }) async {
    if (files.isEmpty) {
      throw const GhCommandException(-1, 'No files were provided to commit.');
    }

    final refResult = await _runner.run([
      'api',
      'repos/$fullName/git/ref/heads/$branch',
    ]);
    final refJson = jsonDecode(refResult.stdout) as Map<String, dynamic>;
    final object = refJson['object'] as Map<String, dynamic>? ?? const {};
    final parentSha = object['sha']?.toString() ?? '';
    if (parentSha.isEmpty) {
      throw const GhCommandException(-1, 'Could not resolve branch head.');
    }

    final commitResult = await _runner.run([
      'api',
      'repos/$fullName/git/commits/$parentSha',
    ]);
    final commitJson =
        jsonDecode(commitResult.stdout) as Map<String, dynamic>;
    final parentTree =
        commitJson['tree'] as Map<String, dynamic>? ?? const {};
    final baseTreeSha = parentTree['sha']?.toString() ?? '';
    if (baseTreeSha.isEmpty) {
      throw const GhCommandException(-1, 'Could not resolve base tree.');
    }

    final treeEntries = <Map<String, dynamic>>[];
    for (final entry in files.entries) {
      final blob = await _runner.run(
        [
          'api',
          '--method',
          'POST',
          'repos/$fullName/git/blobs',
          '--input',
          '-',
        ],
        stdin: jsonEncode({
          'content': entry.value,
          'encoding': 'utf-8',
        }),
      );
      final blobJson = jsonDecode(blob.stdout) as Map<String, dynamic>;
      final blobSha = blobJson['sha']?.toString() ?? '';
      if (blobSha.isEmpty) {
        throw GhCommandException(
          -1,
          'Could not create Git blob for ${entry.key}.',
        );
      }

      treeEntries.add({
        'path': entry.key,
        'mode': '100644',
        'type': 'blob',
        'sha': blobSha,
      });
    }

    final treeResult = await _runner.run(
      [
        'api',
        '--method',
        'POST',
        'repos/$fullName/git/trees',
        '--input',
        '-',
      ],
      stdin: jsonEncode({
        'base_tree': baseTreeSha,
        'tree': treeEntries,
      }),
    );
    final treeJson = jsonDecode(treeResult.stdout) as Map<String, dynamic>;
    final treeSha = treeJson['sha']?.toString() ?? '';
    if (treeSha.isEmpty) {
      throw const GhCommandException(-1, 'Could not create Git tree.');
    }

    final newCommit = await _runner.run(
      [
        'api',
        '--method',
        'POST',
        'repos/$fullName/git/commits',
        '--input',
        '-',
      ],
      stdin: jsonEncode({
        'message': message,
        'tree': treeSha,
        'parents': [parentSha],
      }),
    );
    final newCommitJson =
        jsonDecode(newCommit.stdout) as Map<String, dynamic>;
    final newCommitSha = newCommitJson['sha']?.toString() ?? '';
    if (newCommitSha.isEmpty) {
      throw const GhCommandException(-1, 'Could not create Git commit.');
    }

    await _runner.run(
      [
        'api',
        '--method',
        'PATCH',
        'repos/$fullName/git/refs/heads/$branch',
        '--input',
        '-',
      ],
      stdin: jsonEncode({
        'sha': newCommitSha,
        'force': false,
      }),
    );

    return newCommitSha;
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
