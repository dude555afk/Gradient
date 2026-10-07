import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/github/github_page_context.dart';

void main() {
  test('parses repository file pages', () {
    final context = GitHubPageContext.parse(
      'https://github.com/openai/example/blob/main/lib/app.dart',
    );

    expect(context.fullName, 'openai/example');
    expect(context.kind, 'file');
    expect(context.branch, 'main');
    expect(context.filePath, 'lib/app.dart');
  });

  test('parses pull request pages', () {
    final context = GitHubPageContext.parse(
      'https://github.com/openai/example/pull/42',
    );

    expect(context.fullName, 'openai/example');
    expect(context.kind, 'pull_request');
    expect(context.number, 42);
  });

  test('ignores account settings as repository context', () {
    final context = GitHubPageContext.parse(
      'https://github.com/settings/profile',
    );

    expect(context.fullName, isNull);
  });
}
