import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/core/models/model_router.dart';

void main() {
  const router = ModelRouter();

  test('routes workflow debugging to reasoning', () {
    expect(
      router.select('Why is my GitHub workflow failing?'),
      ModelRole.reasoning,
    );
  });

  test('routes implementation to coding', () {
    expect(
      router.select('Implement this feature across multiple files'),
      ModelRole.coding,
    );
  });

  test('routes screenshots to vision', () {
    expect(
      router.select('Check this screenshot for a UI bug'),
      ModelRole.vision,
    );
  });
}
