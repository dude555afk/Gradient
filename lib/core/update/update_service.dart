import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class GradientUpdateInfo {
  const GradientUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseUrl,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String releaseUrl;
}

class GradientUpdateStatus {
  const GradientUpdateStatus({
    required this.currentVersionName,
    required this.currentVersionCode,
    required this.latest,
  });

  final String currentVersionName;
  final int currentVersionCode;
  final GradientUpdateInfo latest;

  bool get updateAvailable => latest.versionCode > currentVersionCode;
}

class GradientUpdateService {
  GradientUpdateService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const String _manifestUrl =
      'https://github.com/dude555afk/Gradient/releases/download/gradient-latest/update.json';

  final http.Client _client;
  final bool _ownsClient;

  Future<GradientUpdateStatus> check() async {
    final package = await PackageInfo.fromPlatform();

    final response = await _client.get(
      Uri.parse(
        '$_manifestUrl?ts=${DateTime.now().millisecondsSinceEpoch}',
      ),
      headers: const {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GradientUpdateException(
        'Update check failed with HTTP ${response.statusCode}.',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    final latest = GradientUpdateInfo(
      versionName: (json['versionName'] ?? '').toString(),
      versionCode: _asInt(json['versionCode']),
      apkUrl: (json['apkUrl'] ?? '').toString(),
      releaseUrl: (json['releaseUrl'] ?? '').toString(),
    );

    if (latest.versionCode <= 0 || latest.apkUrl.isEmpty) {
      throw const GradientUpdateException(
        'The update channel returned invalid metadata.',
      );
    }

    return GradientUpdateStatus(
      currentVersionName: package.version,
      currentVersionCode: int.tryParse(package.buildNumber) ?? 0,
      latest: latest,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class GradientUpdateException implements Exception {
  const GradientUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
