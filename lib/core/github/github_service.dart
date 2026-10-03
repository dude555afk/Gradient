import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_models.dart';

class GitHubService {
  GitHubService({required this.token, http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String token;
  final http.Client _client;
  final bool _ownsClient;

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Map<String, String> get _jsonHeaders => {
        ..._headers,
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> currentUser() async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/user'),
      headers: _headers,
    );
    return _object(response);
  }

  Future<List<GitHubRepository>> listRepositories() async {
    final response = await _client.get(
      Uri.parse(
        'https://api.github.com/user/repos'
        '?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member',
      ),
      headers: _headers,
    );
    return _list(response)
        .map((e) => GitHubRepository.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> repository(String fullName) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/repos/$fullName'),
      headers: _headers,
    );
    return _object(response);
  }

  Future<List<String>> listBranches(String fullName) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/repos/$fullName/branches?per_page=100'),
      headers: _headers,
    );
    return _list(response)
        .map((e) => (e as Map<String, dynamic>)['name'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<GitHubEntry>> listContents(
    String fullName, {
    String path = '',
    String? ref,
  }) async {
    final query = ref == null ? null : {'ref': ref};
    final uri = Uri.https(
      'api.github.com',
      '/repos/$fullName/contents/$path',
      query,
    );
    final response = await _client.get(uri, headers: _headers);
    return _list(response)
        .map((e) => GitHubEntry.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<GitHubFile> readFile(
    String fullName,
    String path, {
    String? ref,
  }) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$fullName/contents/$path',
      ref == null ? null : {'ref': ref},
    );

    final response = await _client.get(uri, headers: _headers);
    final json = _object(response);
    final encoded = (json['content'] as String? ?? '').replaceAll('\n', '');

    return GitHubFile(
      path: path,
      sha: json['sha'] as String? ?? '',
      content: utf8.decode(base64.decode(encoded)),
    );
  }

  Future<String> createBranch({
    required String fullName,
    required String branch,
    required String from,
  }) async {
    final sourceResponse = await _client.get(
      Uri.parse(
        'https://api.github.com/repos/$fullName/git/ref/heads/$from',
      ),
      headers: _headers,
    );
    final source = _object(sourceResponse);
    final object = source['object'] as Map<String, dynamic>;
    final sha = object['sha'] as String;

    final response = await _client.post(
      Uri.parse('https://api.github.com/repos/$fullName/git/refs'),
      headers: _jsonHeaders,
      body: jsonEncode({'ref': 'refs/heads/$branch', 'sha': sha}),
    );
    _object(response);
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
    final uri = Uri.parse(
      'https://api.github.com/repos/$fullName/contents/$path',
    );

    final response = await _client.put(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'message': message,
        'content': base64.encode(utf8.encode(content)),
        'branch': branch,
        if (currentSha != null && currentSha.isNotEmpty) 'sha': currentSha,
      }),
    );

    final json = _object(response);
    return ((json['commit'] as Map?)?['sha'] as String?) ?? '';
  }

  Future<List<GitHubWorkflowRun>> listWorkflowRuns(
    String fullName, {
    int count = 10,
  }) async {
    final response = await _client.get(
      Uri.parse(
        'https://api.github.com/repos/$fullName/actions/runs?per_page=$count',
      ),
      headers: _headers,
    );
    final json = _object(response);
    final runs = json['workflow_runs'] as List<dynamic>? ?? const [];
    return runs
        .map(
          (e) => GitHubWorkflowRun.fromJson(e as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<List<GitHubWorkflowJob>> listWorkflowJobs(
    String fullName,
    int runId,
  ) async {
    final response = await _client.get(
      Uri.parse(
        'https://api.github.com/repos/$fullName/actions/runs/$runId/jobs',
      ),
      headers: _headers,
    );
    final json = _object(response);
    final jobs = json['jobs'] as List<dynamic>? ?? const [];
    return jobs
        .map(
          (e) => GitHubWorkflowJob.fromJson(e as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<String> workflowJobLog(String fullName, int jobId) async {
    final response = await _client.get(
      Uri.parse(
        'https://api.github.com/repos/$fullName/actions/jobs/$jobId/logs',
      ),
      headers: _headers,
    );
    _ensureSuccess(response);
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<String> createPullRequest({
    required String fullName,
    required String title,
    required String body,
    required String head,
    required String base,
  }) async {
    final response = await _client.post(
      Uri.parse('https://api.github.com/repos/$fullName/pulls'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'title': title,
        'body': body,
        'head': head,
        'base': base,
      }),
    );
    final json = _object(response);
    return json['html_url'] as String? ?? '';
  }

  Map<String, dynamic> _object(http.Response response) {
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  List<dynamic> _list(http.Response response) {
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List<dynamic>) return decoded;
    throw const FormatException('Expected a JSON list from GitHub.');
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GitHubException(response.statusCode, response.body);
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class GitHubFile {
  const GitHubFile({
    required this.path,
    required this.sha,
    required this.content,
  });

  final String path;
  final String sha;
  final String content;
}

class GitHubException implements Exception {
  const GitHubException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'GitHubException($statusCode): $body';
}
