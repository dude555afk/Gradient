import 'package:flutter/services.dart';

class BackgroundAgentRuntime {
  BackgroundAgentRuntime._();

  static const _channel = MethodChannel('gradient/background');

  static Future<void> start({
    required String taskId,
    required String conversationId,
    required String title,
    String detail = 'Gradient is working…',
  }) async {
    await _channel.invokeMethod<void>('start', {
      'taskId': taskId,
      'conversationId': conversationId,
      'title': title,
      'detail': detail,
    });
  }

  static Future<void> update({
    required String taskId,
    required String detail,
  }) async {
    await _channel.invokeMethod<void>('update', {
      'taskId': taskId,
      'detail': detail,
    });
  }

  static Future<void> stop({required String taskId}) async {
    await _channel.invokeMethod<void>('stop', {'taskId': taskId});
  }
}
