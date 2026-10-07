import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/ai/provider_model_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetches OpenAI-style model data', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://example.com/v1/models');
      expect(request.headers['Authorization'], 'Bearer secret');
      return http.Response(
        '{"data":[{"id":"z/model"},{"id":"a/model","name":"A Model"}]}',
        200,
      );
    });

    final catalog = ProviderModelCatalog(
      baseUrl: 'https://example.com/v1',
      apiKey: 'secret',
      client: client,
    );

    final models = await catalog.fetchModels();

    expect(models.map((e) => e.id), ['a/model', 'z/model']);
    expect(models.first.displayName, 'A Model');
  });

  test('normalizes chat completions URL before fetching models', () {
    final catalog = ProviderModelCatalog(
      baseUrl: 'https://example.com/v1/chat/completions',
      apiKey: '',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      catalog.modelsEndpoint.toString(),
      'https://example.com/v1/models',
    );
  });

  test('supports a top-level models array', () async {
    final catalog = ProviderModelCatalog(
      baseUrl: 'https://example.com/v1',
      apiKey: '',
      client: MockClient(
        (_) async => http.Response(
          '{"models":[{"name":"models/gemini-test","displayName":"Gemini Test"}]}',
          200,
        ),
      ),
    );

    final models = await catalog.fetchModels();

    expect(models.single.id, 'gemini-test');
    expect(models.single.displayName, 'Gemini Test');
  });
}
