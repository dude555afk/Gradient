import 'dart:convert';

import 'package:http/http.dart' as http;

class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class AiTurn {
  const AiTurn({
    required this.content,
    required this.toolCalls,
    required this.assistantMessage,
  });

  final String content;
  final List<AiToolCall> toolCalls;
  final Map<String, dynamic> assistantMessage;
}

class OpenAiCompatibleProvider {
  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.apiKey,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final String apiKey;
  final http.Client _client;
  final bool _ownsClient;

  Uri get _endpoint {
    final clean = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (clean.endsWith('/chat/completions')) return Uri.parse(clean);
    return Uri.parse('$clean/chat/completions');
  }

  Future<AiTurn> complete({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String reasoningEffort = '',
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': 'auto',
      if (reasoningEffort.trim().isNotEmpty)
        'reasoning_effort': reasoningEffort.trim(),
    };

    final response = await _client.post(
      _endpoint,
      headers: {
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) {
      throw const FormatException('Provider returned no choices.');
    }

    final choice = choices.first as Map<String, dynamic>;
    final message = Map<String, dynamic>.from(
      choice['message'] as Map<dynamic, dynamic>,
    );

    final calls = <AiToolCall>[];
    for (final raw in message['tool_calls'] as List<dynamic>? ?? const []) {
      final call = raw as Map<String, dynamic>;
      final function = call['function'] as Map<String, dynamic>? ?? const {};
      final rawArguments = function['arguments'] as String? ?? '{}';
      Map<String, dynamic> arguments;
      try {
        arguments = Map<String, dynamic>.from(
          jsonDecode(rawArguments) as Map<dynamic, dynamic>,
        );
      } catch (_) {
        arguments = <String, dynamic>{'raw': rawArguments};
      }

      calls.add(
        AiToolCall(
          id: call['id'] as String? ?? '',
          name: function['name'] as String? ?? '',
          arguments: arguments,
        ),
      );
    }

    return AiTurn(
      content: (message['content'] as String?) ?? '',
      toolCalls: calls,
      assistantMessage: message,
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class AiProviderException implements Exception {
  const AiProviderException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'AI provider error $statusCode: $body';
}
