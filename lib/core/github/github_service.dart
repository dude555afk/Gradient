import 'dart:convert';

import 'package:http/http.dart' as http;

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

  Future<Map<String, dynamic>> repository(String fullName) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/repos/$fullName'),
      headers: _headers,
    );
    return _jsonObject(response);
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
    final json = _jsonObject(response);
    final encoded = (json['content'] as String? ?? '').replaceAll('\n', '');

    return GitHubFile(
      path: path,
      sha: json['sha'] as String? ?? '',
      content: utf8.decode(base64.decode(encoded)),
    );
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
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'content': base64.encode(utf8.encode(content)),
        'branch': branch,
        if (currentSha != null) 'sha': currentSha,
      }),
    );

    final json = _jsonObject(response);
    return ((json['commit'] as Map?)?['sha'] as String?) ?? '';
  }

  Map<String, dynamic> _jsonObject(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GitHubException(response.statusCode, response.body);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
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
