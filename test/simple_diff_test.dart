import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/diff/simple_diff.dart';

void main() {
  test('shows removed and added lines', () {
    final diff = buildSimpleDiff(
      path: 'lib/a.dart',
      oldText: 'a\nb\nc',
      newText: 'a\nx\nc',
    );

    expect(diff, contains('-b'));
    expect(diff, contains('+x'));
  });
}
