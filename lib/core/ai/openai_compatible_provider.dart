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

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${apiKey.trim()}',
      };

  Map<String, dynamic> _requestBody({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required String reasoningEffort,
    bool stream = false,
  }) {
    return <String, dynamic>{
      'model': model,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': 'auto',
      if (reasoningEffort.trim().isNotEmpty)
        'reasoning_effort': reasoningEffort.trim(),
      if (stream) 'stream': true,
    };
  }

  Future<AiTurn> complete({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String reasoningEffort = '',
  }) async {
    final response = await _client.post(
      _endpoint,
      headers: _headers,
      body: jsonEncode(
        _requestBody(
          model: model,
          messages: messages,
          tools: tools,
          reasoningEffort: reasoningEffort,
        ),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(response.statusCode, response.body);
    }

    return _parseTurn(response.body);
  }

  Future<AiTurn> completeStreaming({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String reasoningEffort = '',
    void Function(String delta)? onDelta,
  }) async {
    final request = http.Request('POST', _endpoint)
      ..headers.addAll(_headers)
      ..body = jsonEncode(
        _requestBody(
          model: model,
          messages: messages,
          tools: tools,
          reasoningEffort: reasoningEffort,
          stream: true,
        ),
      );

    final response = await _client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();

      // Some OpenAI-compatible providers simply do not implement SSE.
      // Fall back to the ordinary endpoint instead of breaking the chat.
      if (response.statusCode == 400 ||
          response.statusCode == 404 ||
          response.statusCode == 422) {
        return complete(
          model: model,
          messages: messages,
          tools: tools,
          reasoningEffort: reasoningEffort,
        );
      }
      throw AiProviderException(response.statusCode, body);
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (!contentType.contains('text/event-stream')) {
      final body = await response.stream.bytesToString();
      return _parseTurn(body);
    }

    final content = StringBuffer();
    final builders = <int, _ToolCallBuilder>{};

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') {
        if (payload == '[DONE]') break;
        continue;
      }

      Map<String, dynamic> event;
      try {
        event = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final choices = event['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) continue;
      final choice = choices.first as Map<String, dynamic>;
      final delta =
          choice['delta'] as Map<String, dynamic>? ?? const <String, dynamic>{};

      final text = delta['content'];
      if (text is String && text.isNotEmpty) {
        content.write(text);
        onDelta?.call(text);
      }

      for (final raw in delta['tool_calls'] as List<dynamic>? ?? const []) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final index = (map['index'] as num?)?.toInt() ?? 0;
        final builder = builders.putIfAbsent(index, _ToolCallBuilder.new);

        final id = map['id'];
        if (id is String && id.isNotEmpty) builder.id = id;

        final function = map['function'];
        if (function is Map) {
          final fn = Map<String, dynamic>.from(function);
          final name = fn['name'];
          if (name is String) builder.name.write(name);
          final arguments = fn['arguments'];
          if (arguments is String) builder.arguments.write(arguments);
        }
      }
    }

    final toolCalls = builders.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final parsedCalls = toolCalls.map((entry) {
      final builder = entry.value;
      Map<String, dynamic> arguments;
      final raw = builder.arguments.toString();
      try {
        arguments = Map<String, dynamic>.from(
          jsonDecode(raw.isEmpty ? '{}' : raw) as Map,
        );
      } catch (_) {
        arguments = <String, dynamic>{'raw': raw};
      }

      return AiToolCall(
        id: builder.id,
        name: builder.name.toString(),
        arguments: arguments,
      );
    }).toList(growable: false);

    final assistantToolCalls = toolCalls.map((entry) {
      final builder = entry.value;
      return {
        'id': builder.id,
        'type': 'function',
        'function': {
          'name': builder.name.toString(),
          'arguments': builder.arguments.toString(),
        },
      };
    }).toList(growable: false);

    final text = content.toString();
    return AiTurn(
      content: text,
      toolCalls: parsedCalls,
      assistantMessage: {
        'role': 'assistant',
        'content': text,
        if (assistantToolCalls.isNotEmpty) 'tool_calls': assistantToolCalls,
      },
    );
  }

  AiTurn _parseTurn(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
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

    final rawContent = message['content'];
    return AiTurn(
      content: rawContent is String ? rawContent : '',
      toolCalls: calls,
      assistantMessage: message,
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class _ToolCallBuilder {
  String id = '';
  final StringBuffer name = StringBuffer();
  final StringBuffer arguments = StringBuffer();
}

class AiProviderException implements Exception {
  const AiProviderException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  bool get retryable =>
      statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504 ||
      statusCode == 529;

  String get friendlyMessage {
    String clean = body.replaceAll(RegExp(r'\s+'), ' ').trim();

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final root = Map<String, dynamic>.from(decoded);
        final error = root['error'];
        if (error is Map) {
          final message = error['message']?.toString().trim();
          if (message != null && message.isNotEmpty) clean = message;

          final metadata = error['metadata'];
          if (metadata is Map) {
            final raw = metadata['raw']?.toString();
            if (raw != null && raw.isNotEmpty) {
              try {
                final nested = jsonDecode(raw);
                if (nested is Map) {
                  final nestedError = nested['error'];
                  if (nestedError is Map) {
                    final nestedMessage =
                        nestedError['message']?.toString().trim();
                    if (nestedMessage != null && nestedMessage.isNotEmpty) {
                      clean = nestedMessage;
                    }
                  }
                }
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}

    clean = clean
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (clean.length > 220) clean = '${clean.substring(0, 220)}…';

    if (statusCode == 429) {
      return clean.isEmpty
          ? 'Too many requests. Try again in a moment or switch models.'
          : clean;
    }
    if (statusCode >= 500) {
      return clean.isEmpty
          ? 'The provider is temporarily unavailable.'
          : clean;
    }
    return clean.isEmpty ? 'Provider error $statusCode.' : clean;
  }

  @override
  String toString() => 'AI provider error $statusCode: $body';
}
