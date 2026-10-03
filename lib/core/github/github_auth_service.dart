import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GitHubDeviceCode {
  const GitHubDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
}

class GitHubAuthService {
  GitHubAuthService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<GitHubDeviceCode> requestDeviceCode(String clientId) async {
    final response = await _client.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': clientId.trim(),
        'scope': 'repo workflow read:user',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('GitHub device flow failed: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return GitHubDeviceCode(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      expiresIn: (json['expires_in'] as num).toInt(),
      interval: ((json['interval'] as num?) ?? 5).toInt(),
    );
  }

  Future<void> openVerification(GitHubDeviceCode code) async {
    final uri = Uri.parse(code.verificationUri);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw StateError('Could not open GitHub authorization page.');
    }
  }

  Future<String> pollForToken({
    required String clientId,
    required GitHubDeviceCode code,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
    var interval = code.interval;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: interval));
      final response = await _client.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': clientId.trim(),
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final token = json['access_token'] as String?;
      if (token != null && token.isNotEmpty) return token;

      switch (json['error'] as String?) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        case 'expired_token':
          throw StateError('GitHub authorization code expired.');
        case 'access_denied':
          throw StateError('GitHub authorization was denied.');
        default:
          throw StateError(
            'GitHub authorization failed: '
            '${json['error_description'] ?? json['error'] ?? response.body}',
          );
      }
    }

    throw StateError('GitHub authorization timed out.');
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
