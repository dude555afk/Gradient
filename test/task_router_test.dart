import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/core/agent/task_router.dart';
import 'package:gradient/core/models/model_router.dart';

void main() {
  const router = TaskRouter();

  test('image attachment forces vision model even without vision words', () {
    final route = router.route(
      'What is wrong here?',
      hasImages: true,
    );

    expect(route.model, ModelRole.vision);
  });

  test('non-image task still uses normal model routing', () {
    final route = router.route('Fix this workflow failure');

    expect(route.model, ModelRole.reasoning);
  });
}
