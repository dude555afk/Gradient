import 'dart:io';

import 'package:flutter/services.dart';

class GhCommandResult {
  const GhCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class GhCommandRunner {
  GhCommandRunner({required this.token});

  static const _channel = MethodChannel('gradient/native');

  final String token;
  String? _binaryPath;

  Future<String> binaryPath() async {
    final cached = _binaryPath;
    if (cached != null) return cached;

    if (!Platform.isAndroid) {
      _binaryPath = 'gh';
      return 'gh';
    }

    final nativeLibraryDir =
        await _channel.invokeMethod<String>('nativeLibraryDir');
    if (nativeLibraryDir == null || nativeLibraryDir.isEmpty) {
      throw const GhCommandException(
        -1,
        'Gradient could not locate its bundled GitHub CLI runtime.',
      );
    }

    final path = '$nativeLibraryDir/libgh.so';
    _binaryPath = path;
    return path;
  }

  Future<Directory> configDirectory() async {
    final dir = Directory(
      '${Directory.systemTemp.path}/gradient-gh',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<Map<String, String>> commandEnvironment() async {
    final configDir = await configDirectory();
    return {
      'GH_PAGER': 'cat',
      'PAGER': 'cat',
      'NO_COLOR': '1',
      'CLICOLOR': '0',
      'GH_PROMPT_DISABLED': '1',
      'GH_CONFIG_DIR': configDir.path,
      'HOME': configDir.path,
      'TMPDIR': Directory.systemTemp.path,
      if (token.trim().isNotEmpty) 'GH_TOKEN': token.trim(),
    };
  }

  Future<void> clearCliConfig() async {
    final dir = await configDirectory();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  Future<GhCommandResult> run(
    List<String> args, {
    String? stdin,
    Duration timeout = const Duration(seconds: 45),
    bool throwOnError = true,
  }) async {
    final binary = await binaryPath();
    final environment = await commandEnvironment();

    final process = await Process.start(
      binary,
      args,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );

    if (stdin != null) {
      process.stdin.write(stdin);
    }
    await process.stdin.close();

    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();

    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );

    final out = await stdoutFuture;
    final err = await stderrFuture;

    final result = GhCommandResult(
      exitCode: exitCode,
      stdout: out,
      stderr: err,
    );

    if (throwOnError && exitCode != 0) {
      throw GhCommandException(
        exitCode,
        err.trim().isEmpty ? out.trim() : err.trim(),
      );
    }

    return result;
  }

  Future<String> version() async {
    final result = await run(const ['--version']);
    return result.stdout.trim();
  }
}

class GhCommandException implements Exception {
  const GhCommandException(this.exitCode, this.message);

  final int exitCode;
  final String message;

  @override
  String toString() => 'gh failed ($exitCode): $message';
}
