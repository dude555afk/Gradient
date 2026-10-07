import 'dart:convert';

import 'package:http/http.dart' as http;

class ProviderModel {
  const ProviderModel({
    required this.id,
    required this.displayName,
    this.supportsVision = false,
    this.supportsReasoning = false,
    this.supportsTools = false,
    this.contextLength,
  });

  final String id;
  final String displayName;
  final bool supportsVision;
  final bool supportsReasoning;
  final bool supportsTools;
  final int? contextLength;

  String get capabilitySummary {
    final parts = <String>[
      if (supportsVision) 'Vision',
      if (supportsReasoning) 'Reasoning',
      if (supportsTools) 'Tools',
      if (contextLength != null) _formatContext(contextLength!),
    ];
    return parts.join(' • ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'supportsVision': supportsVision,
        'supportsReasoning': supportsReasoning,
        'supportsTools': supportsTools,
        if (contextLength != null) 'contextLength': contextLength,
      };

  factory ProviderModel.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    return ProviderModel(
      id: id,
      displayName:
          json['displayName']?.toString().trim().isNotEmpty == true
              ? json['displayName'].toString().trim()
              : id,
      supportsVision: json['supportsVision'] as bool? ?? false,
      supportsReasoning: json['supportsReasoning'] as bool? ?? false,
      supportsTools: json['supportsTools'] as bool? ?? false,
      contextLength: _asInt(json['contextLength']),
    );
  }

  static ProviderModel fromProviderEntry(Object raw) {
    if (raw is String) {
      final id = raw.trim();
      final inferred = _inferFromId(id);
      return ProviderModel(
        id: id,
        displayName: id,
        supportsVision: inferred.vision,
        supportsReasoning: inferred.reasoning,
        supportsTools: inferred.tools,
      );
    }

    if (raw is! Map) {
      return const ProviderModel(id: '', displayName: '');
    }

    final map = Map<String, dynamic>.from(raw);
    var id = (map['id'] ?? map['name'] ?? '').toString().trim();
    if (id.startsWith('models/')) {
      id = id.substring('models/'.length);
    }

    var displayName =
        (map['display_name'] ??
                map['displayName'] ??
                map['name'] ??
                map['id'] ??
                '')
            .toString()
            .trim();
    if (displayName.startsWith('models/')) {
      displayName = displayName.substring('models/'.length);
    }

    final supported = <String>{};
    for (final rawParam in (map['supported_parameters'] ??
            map['supportedParameters'] ??
            const <dynamic>[]) as Iterable<dynamic>) {
      supported.add(rawParam.toString().toLowerCase());
    }

    final architecture =
        map['architecture'] is Map
            ? Map<String, dynamic>.from(map['architecture'] as Map)
            : const <String, dynamic>{};

    final modalities = <String>{};
    final modalityRaw = architecture['input_modalities'] ??
        architecture['inputModalities'] ??
        map['input_modalities'] ??
        map['inputModalities'];
    if (modalityRaw is Iterable) {
      modalities.addAll(
        modalityRaw.map((e) => e.toString().toLowerCase()),
      );
    } else if (modalityRaw != null) {
      modalities.add(modalityRaw.toString().toLowerCase());
    }

    final inferred = _inferFromId(id);
    final supportsVision =
        modalities.any((e) => e.contains('image')) ||
        supported.any((e) => e.contains('image')) ||
        inferred.vision;
    final supportsReasoning =
        supported.contains('reasoning') ||
        supported.contains('reasoning_effort') ||
        supported.any((e) => e.contains('thinking')) ||
        inferred.reasoning;
    final supportsTools =
        supported.contains('tools') ||
        supported.contains('tool_choice') ||
        supported.any((e) => e.contains('function')) ||
        inferred.tools;

    final contextLength = _asInt(
      map['context_length'] ??
          map['contextLength'] ??
          map['context_window'] ??
          map['contextWindow'] ??
          architecture['context_length'],
    );

    return ProviderModel(
      id: id,
      displayName: displayName.isEmpty ? id : displayName,
      supportsVision: supportsVision,
      supportsReasoning: supportsReasoning,
      supportsTools: supportsTools,
      contextLength: contextLength,
    );
  }

  static ({bool vision, bool reasoning, bool tools}) _inferFromId(
    String id,
  ) {
    final text = id.toLowerCase();
    final vision = [
      'vision',
      '-vl',
      'vl-',
      'gpt-4o',
      'gpt-5',
      'gemini',
      'claude-3',
      'claude-4',
      'pixtral',
      'llava',
      'qwen2.5-vl',
      'qwen3-vl',
    ].any(text.contains);

    final reasoning = [
      'reasoning',
      'thinking',
      'deepseek-r1',
      'qwq',
      'o1',
      'o3',
      'o4',
      'gpt-5',
      'glm-5',
    ].any(text.contains);

    final tools = ![
      'embedding',
      'rerank',
      'moderation',
      'tts',
      'whisper',
    ].any(text.contains);

    return (vision: vision, reasoning: reasoning, tools: tools);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _formatContext(int value) {
    if (value >= 1000000) {
      final n = value / 1000000;
      return '${n == n.roundToDouble() ? n.toInt() : n.toStringAsFixed(1)}M ctx';
    }
    if (value >= 1000) {
      final n = value / 1000;
      return '${n == n.roundToDouble() ? n.toInt() : n.toStringAsFixed(1)}K ctx';
    }
    return '$value ctx';
  }
}

class ProviderModelCatalog {
  ProviderModelCatalog({
    required this.baseUrl,
    required this.apiKey,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final String apiKey;
  final http.Client _client;
  final bool _ownsClient;

  Uri get modelsEndpoint {
    var clean = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (clean.endsWith('/chat/completions')) {
      clean = clean.substring(
        0,
        clean.length - '/chat/completions'.length,
      );
    } else if (clean.endsWith('/responses')) {
      clean = clean.substring(0, clean.length - '/responses'.length);
    }

    if (clean.isEmpty) {
      throw const FormatException('Provider base URL is empty.');
    }

    if (clean.endsWith('/models')) return Uri.parse(clean);
    return Uri.parse('$clean/models');
  }

  Future<List<ProviderModel>> fetchModels() async {
    final response = await _client.get(
      modelsEndpoint,
      headers: {
        'Accept': 'application/json',
        if (apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${apiKey.trim()}',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderModelFetchException(
        response.statusCode,
        response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    final rawItems = switch (decoded) {
      Map<String, dynamic> map when map['data'] is List<dynamic> =>
        map['data'] as List<dynamic>,
      Map<String, dynamic> map when map['models'] is List<dynamic> =>
        map['models'] as List<dynamic>,
      List<dynamic> list => list,
      _ => const <dynamic>[],
    };

    final byId = <String, ProviderModel>{};

    for (final raw in rawItems) {
      final model = ProviderModel.fromProviderEntry(raw);
      if (model.id.isEmpty) continue;
      byId[model.id] = model;
    }

    final models = byId.values.toList(growable: false)
      ..sort(
        (a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()),
      );

    return models;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class ProviderModelFetchException implements Exception {
  const ProviderModelFetchException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final clipped =
        compact.length > 300 ? '${compact.substring(0, 300)}…' : compact;
    return 'Model fetch failed (HTTP $statusCode): $clipped';
  }
}
