import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/core/skills/skill_router.dart';

void main() {
  const router = SkillRouter();

  test('selects CI and Android skills for Gradle workflow failures', () {
    final ids = router
        .select('Android Gradle workflow build failed')
        .map((e) => e.id)
        .toSet();

    expect(ids, contains('ci'));
    expect(ids, contains('android'));
  });
}
