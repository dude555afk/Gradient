import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_router.dart';

class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.defaultModel,
    required this.fastModel,
    required this.codingModel,
    required this.reasoningModel,
    required this.searchModel,
    required this.visionModel,
    required this.reviewerModel,
    required this.reasoningEffort,
    required this.githubClientId,
  });

  final String baseUrl;
  final String defaultModel;
  final String fastModel;
  final String codingModel;
  final String reasoningModel;
  final String searchModel;
  final String visionModel;
  final String reviewerModel;
  final String reasoningEffort;
  final String githubClientId;

  bool get providerReady =>
      baseUrl.trim().isNotEmpty && defaultModel.trim().isNotEmpty;

  String modelFor(ModelRole role) {
    final candidate = switch (role) {
      ModelRole.fast => fastModel,
      ModelRole.coding => codingModel,
      ModelRole.reasoning => reasoningModel,
      ModelRole.search => searchModel,
      ModelRole.vision => visionModel,
      ModelRole.reviewer => reviewerModel,
    };
    return candidate.trim().isEmpty ? defaultModel.trim() : candidate.trim();
  }

  AiSettings copyWith({
    String? baseUrl,
    String? defaultModel,
    String? fastModel,
    String? codingModel,
    String? reasoningModel,
    String? searchModel,
    String? visionModel,
    String? reviewerModel,
    String? reasoningEffort,
    String? githubClientId,
  }) {
    return AiSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      defaultModel: defaultModel ?? this.defaultModel,
      fastModel: fastModel ?? this.fastModel,
      codingModel: codingModel ?? this.codingModel,
      reasoningModel: reasoningModel ?? this.reasoningModel,
      searchModel: searchModel ?? this.searchModel,
      visionModel: visionModel ?? this.visionModel,
      reviewerModel: reviewerModel ?? this.reviewerModel,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      githubClientId: githubClientId ?? this.githubClientId,
    );
  }
}

class AppSettingsStore {
  AppSettingsStore({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _secure = secureStorage;

  static const _apiKeyKey = 'ai_api_key_v1';
  static const _githubTokenKey = 'github_token_v1';

  final FlutterSecureStorage _secure;

  Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AiSettings(
      baseUrl:
          prefs.getString('ai_base_url') ?? 'https://openrouter.ai/api/v1',
      defaultModel: prefs.getString('ai_default_model') ?? '',
      fastModel: prefs.getString('ai_fast_model') ?? '',
      codingModel: prefs.getString('ai_coding_model') ?? '',
      reasoningModel: prefs.getString('ai_reasoning_model') ?? '',
      searchModel: prefs.getString('ai_search_model') ?? '',
      visionModel: prefs.getString('ai_vision_model') ?? '',
      reviewerModel: prefs.getString('ai_reviewer_model') ?? '',
      reasoningEffort: prefs.getString('ai_reasoning_effort') ?? '',
      githubClientId: prefs.getString('github_client_id') ?? '',
    );
  }

  Future<void> save(AiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('ai_base_url', settings.baseUrl.trim()),
      prefs.setString('ai_default_model', settings.defaultModel.trim()),
      prefs.setString('ai_fast_model', settings.fastModel.trim()),
      prefs.setString('ai_coding_model', settings.codingModel.trim()),
      prefs.setString('ai_reasoning_model', settings.reasoningModel.trim()),
      prefs.setString('ai_search_model', settings.searchModel.trim()),
      prefs.setString('ai_vision_model', settings.visionModel.trim()),
      prefs.setString('ai_reviewer_model', settings.reviewerModel.trim()),
      prefs.setString('ai_reasoning_effort', settings.reasoningEffort.trim()),
      prefs.setString('github_client_id', settings.githubClientId.trim()),
    ]);
  }

  Future<String> apiKey() async =>
      (await _secure.read(key: _apiKeyKey)) ?? '';

  Future<void> setApiKey(String value) async {
    if (value.trim().isEmpty) {
      await _secure.delete(key: _apiKeyKey);
    } else {
      await _secure.write(key: _apiKeyKey, value: value.trim());
    }
  }

  Future<String> githubToken() async =>
      (await _secure.read(key: _githubTokenKey)) ?? '';

  Future<void> setGithubToken(String value) async {
    if (value.trim().isEmpty) {
      await _secure.delete(key: _githubTokenKey);
    } else {
      await _secure.write(key: _githubTokenKey, value: value.trim());
    }
  }

  Future<void> clearGithubToken() => _secure.delete(key: _githubTokenKey);
}
