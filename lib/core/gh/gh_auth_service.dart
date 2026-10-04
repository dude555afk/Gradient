import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'gh_command_runner.dart';

class GhAuthPrompt {
  const GhAuthPrompt({
    required this.code,
    required this.url,
  });

  final String code;
  final String url;
}

class GhAuthService {
  GhAuthService() : _runner = GhCommandRunner(token: '');

  final GhCommandRunner _runner;
  Process? _process;

  Future<String> login({
    required void Function(GhAuthPrompt prompt) onPrompt,
  }) async {
    await _runner.clearCliConfig();

    final binary = await _runner.binaryPath();
    final environment = await _runner.commandEnvironment();
    final process = await Process.start(
      binary,
      const [
        'auth',
        'login',
        '--hostname',
        'github.com',
        '--web',
        '--git-protocol',
        'https',
        '--skip-ssh-key',
        '--insecure-storage',
      ],
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    _process = process;

    final stderr = StringBuffer();
    final stdout = StringBuffer();

    var code = '';
    var url = 'https://github.com/login/device';
    var browserOpened = false;

    Future<void> consume(
      Stream<List<int>> source,
      StringBuffer buffer,
    ) async {
      await for (final line in source
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        buffer.writeln(line);

        final codeMatch = RegExp(
          r'\b[A-Z0-9]{4}-[A-Z0-9]{4}\b',
        ).firstMatch(line);
        if (codeMatch != null) {
          code = codeMatch.group(0) ?? code;
          onPrompt(GhAuthPrompt(code: code, url: url));
        }

        final urlMatch = RegExp(r'https://[^\s]+').firstMatch(line);
        if (urlMatch != null) {
          url = (urlMatch.group(0) ?? url)
              .replaceAll(RegExp(r'[)>.,]+$'), '');
          onPrompt(GhAuthPrompt(code: code, url: url));

          if (!browserOpened) {
            browserOpened = true;
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            }
          }
        }
      }
    }

    final stderrDone = consume(process.stderr, stderr);
    final stdoutDone = consume(process.stdout, stdout);

    final exitCode = await process.exitCode.timeout(
      const Duration(minutes: 6),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );

    await Future.wait([stderrDone, stdoutDone]);
    _process = null;

    if (exitCode != 0) {
      await _runner.clearCliConfig();
      final message = stderr.toString().trim().isNotEmpty
          ? stderr.toString().trim()
          : stdout.toString().trim();
      throw GhCommandException(
        exitCode,
        message.isEmpty ? 'GitHub login failed.' : message,
      );
    }

    final tokenResult = await _runner.run(
      const ['auth', 'token', '--hostname', 'github.com'],
    );
    final token = tokenResult.stdout.trim();

    await _runner.clearCliConfig();

    if (token.isEmpty) {
      throw const GhCommandException(
        -1,
        'GitHub CLI authenticated but returned no token.',
      );
    }

    return token;
  }

  void cancel() {
    _process?.kill(ProcessSignal.sigkill);
    _process = null;
  }
}
