import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class GradientUpdateInfo {
  const GradientUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseUrl,
    required this.applicationId,
    required this.signingCertificateSha256,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String releaseUrl;
  final String applicationId;
  final String signingCertificateSha256;
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
  static const String _expectedApplicationId = 'com.dude555afk.gradient';
  static const String _expectedSigningSha256 =
      '26:AB:CC:AC:47:CE:61:2B:24:6A:B1:4E:E7:0E:CE:3F:5D:02:12:00:3E:69:4E:90:21:31:E9:89:A3:4E:74:9B';

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
      applicationId: (json['applicationId'] ?? '').toString(),
      signingCertificateSha256:
          (json['signingCertificateSha256'] ?? '').toString().toUpperCase(),
    );

    if (latest.versionCode <= 0 || latest.apkUrl.isEmpty) {
      throw const GradientUpdateException(
        'The update channel returned invalid metadata.',
      );
    }

    if (latest.applicationId != _expectedApplicationId) {
      throw const GradientUpdateException(
        'Update rejected because its Android package ID does not match Gradient.',
      );
    }

    if (latest.signingCertificateSha256 != _expectedSigningSha256) {
      throw const GradientUpdateException(
        'Update rejected because its signing certificate does not match Gradient.',
      );
    }

    final apkUri = Uri.tryParse(latest.apkUrl);
    if (apkUri == null ||
        apkUri.scheme != 'https' ||
        apkUri.host.toLowerCase() != 'github.com') {
      throw const GradientUpdateException(
        'Update rejected because its APK URL is not a trusted GitHub URL.',
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
