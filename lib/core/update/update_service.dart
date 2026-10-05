import 'dart:io';

import 'package:flutter/services.dart';
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

  static const MethodChannel _native = MethodChannel('gradient/native');
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

    final json = _decodeJson(response.body);

    final latest = GradientUpdateInfo(
      versionName: (json['versionName'] ?? '').toString(),
      versionCode: _asInt(json['versionCode']),
      apkUrl: (json['apkUrl'] ?? '').toString(),
      releaseUrl: (json['releaseUrl'] ?? '').toString(),
      applicationId: (json['applicationId'] ?? '').toString(),
      signingCertificateSha256:
          (json['signingCertificateSha256'] ?? '').toString().toUpperCase(),
    );

    _validateManifest(latest);

    return GradientUpdateStatus(
      currentVersionName: package.version,
      currentVersionCode: int.tryParse(package.buildNumber) ?? 0,
      latest: latest,
    );
  }

  Future<String> downloadAndInstall(
    GradientUpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    _validateManifest(info);

    final directory = Directory(
      '${Directory.systemTemp.path}/gradient-updates',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/Gradient-update.apk');
    if (await file.exists()) {
      await file.delete();
    }

    final request = http.Request('GET', Uri.parse(info.apkUrl))
      ..headers['Cache-Control'] = 'no-cache';
    final response = await _client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GradientUpdateException(
        'APK download failed with HTTP ${response.statusCode}.',
      );
    }

    final total = response.contentLength;
    var received = 0;
    final sink = file.openWrite();

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }

    if (!await file.exists() || await file.length() < 1024 * 1024) {
      throw const GradientUpdateException(
        'Downloaded APK is missing or unexpectedly small.',
      );
    }

    try {
      final result = await _native.invokeMethod<String>(
        'installApk',
        {
          'path': file.path,
          'expectedPackage': _expectedApplicationId,
          'expectedCertificateSha256': _expectedSigningSha256,
        },
      );
      return result ?? 'installer_opened';
    } on PlatformException catch (error) {
      throw GradientUpdateException(
        error.message ?? 'Android rejected the downloaded update.',
      );
    }
  }

  static Map<String, dynamic> _decodeJson(String body) {
    try {
      final value = Uri.decodeFull(body) == body ? body : body;
      final decoded = const JsonDecoder().convert(value);
      return Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      throw const GradientUpdateException(
        'The update channel returned invalid JSON.',
      );
    }
  }

  static void _validateManifest(GradientUpdateInfo latest) {
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
