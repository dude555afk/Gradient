import 'dart:convert';

import 'package:http/http.dart' as http;

class ProviderModel {
  const ProviderModel({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
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
      String id = '';
      String displayName = '';

      if (raw is String) {
        id = raw.trim();
        displayName = id;
      } else if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        id = (map['id'] ?? map['name'] ?? '').toString().trim();
        if (id.startsWith('models/')) {
          id = id.substring('models/'.length);
        }

        displayName =
            (map['display_name'] ??
                    map['displayName'] ??
                    map['name'] ??
                    map['id'] ??
                    '')
                .toString()
                .trim();
        if (displayName.startsWith('models/')) {
          displayName =
              displayName.substring('models/'.length);
        }
      }

      if (id.isEmpty) continue;
      byId[id] = ProviderModel(
        id: id,
        displayName: displayName.isEmpty ? id : displayName,
      );
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
