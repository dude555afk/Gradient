import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_router.dart';

class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.defaultModel,
    required this.fastModel,
    required this.codingModel,
    required this.debuggingModel,
    required this.reasoningModel,
    required this.searchModel,
    required this.visionModel,
    required this.ocrModel,
    required this.reviewerModel,
    required this.explainerModel,
    required this.fallbackModels,
    required this.roleReasoningEffort,
    required this.roleWebEnabled,
    required this.maxHistoryMessages,
    required this.reasoningEffort,
    required this.githubClientId,
    required this.preferFreeModels,
    this.availableModels = const [],
  });

  final String baseUrl;
  final String defaultModel;
  final String fastModel;
  final String codingModel;
  final String debuggingModel;
  final String reasoningModel;
  final String searchModel;
  final String visionModel;
  final String ocrModel;
  final String reviewerModel;
  final String explainerModel;

  /// Ordered fallback model ids, keyed by [ModelRole.key].
  final Map<String, List<String>> fallbackModels;

  /// Optional per-role reasoning effort override.
  final Map<String, String> roleReasoningEffort;

  /// Optional per-role web access. Missing values default to true.
  final Map<String, bool> roleWebEnabled;

  /// Number of recent chat messages sent to the model.
  final int maxHistoryMessages;

  final String reasoningEffort;
  final String githubClientId;

  /// When enabled, routing prefers configured model ids that look free.
  /// Explicit role primaries always remain first.
  final bool preferFreeModels;

  /// Models returned by the provider's model catalogue. These are used as
  /// automatic fallbacks after explicit role fallbacks.
  final List<String> availableModels;

  bool get providerReady =>
      baseUrl.trim().isNotEmpty && defaultModel.trim().isNotEmpty;

  String primaryModelFor(ModelRole role) {
    final candidate = switch (role) {
      ModelRole.general => defaultModel,
      ModelRole.fast => fastModel,
      ModelRole.coding => codingModel,
      ModelRole.debugging => debuggingModel,
      ModelRole.reasoning => reasoningModel,
      ModelRole.research => searchModel,
      ModelRole.vision => visionModel,
      ModelRole.ocr => ocrModel,
      ModelRole.reviewer => reviewerModel,
      ModelRole.explainer => explainerModel,
    };
    return candidate.trim().isEmpty ? defaultModel.trim() : candidate.trim();
  }

  List<String> modelCandidates(ModelRole role) {
    final explicit = <String>[
      primaryModelFor(role),
      ...?fallbackModels[role.key],
      if (role != ModelRole.general) defaultModel,
    ];

    final automatic = _automaticFallbacks(role);
    final ordered = <String>[
      ...explicit,
      ...automatic,
    ];

    final seen = <String>{};
    final normalized = <String>[];
    for (final raw in ordered) {
      final model = raw.trim();
      if (model.isEmpty || !seen.add(model)) continue;
      normalized.add(model);
    }

    if (!preferFreeModels || normalized.length < 2) return normalized;

    final primary = normalized.first;
    final rest = normalized.skip(1).toList(growable: false)
      ..sort((a, b) {
        final af = _looksFree(a) ? 0 : 1;
        final bf = _looksFree(b) ? 0 : 1;
        if (af != bf) return af.compareTo(bf);
        return _roleScore(b, role).compareTo(_roleScore(a, role));
      });
    return [primary, ...rest];
  }

  List<String> _automaticFallbacks(ModelRole role) {
    final primary = primaryModelFor(role).toLowerCase();
    final configured = <String>{
      primaryModelFor(role).toLowerCase(),
      defaultModel.toLowerCase(),
      ...?fallbackModels[role.key]?.map((e) => e.toLowerCase()),
    };

    final candidates = availableModels
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !configured.contains(e.toLowerCase()))
        .where((e) {
          if (role != ModelRole.vision && role != ModelRole.ocr) return true;
          final id = e.toLowerCase();
          return _containsAny(id, const [
            'vision',
            '-vl',
            '/vl',
            'qwen-vl',
            'qwen2.5-vl',
            'gemini',
            'pixtral',
            'multimodal',
          ]);
        })
        .toList(growable: false);

    candidates.sort((a, b) {
      final freeA = _looksFree(a) ? 1 : 0;
      final freeB = _looksFree(b) ? 1 : 0;
      if (preferFreeModels && freeA != freeB) return freeB.compareTo(freeA);
      final score = _roleScore(b, role).compareTo(_roleScore(a, role));
      if (score != 0) return score;
      return a.compareTo(b);
    });

    // Keep the fallback chain bounded so one bad request cannot walk the
    // provider's entire model catalogue.
    return candidates.take(4).toList(growable: false);
  }

  static int _roleScore(String model, ModelRole role) {
    final id = model.toLowerCase();
    var score = 0;
    void boost(List<String> needles, int value) {
      if (_containsAny(id, needles)) score += value;
    }

    switch (role) {
      case ModelRole.coding:
      case ModelRole.debugging:
        boost(const ['coder', 'code', 'qwen', 'deepseek', 'glm', 'step'], 6);
        break;
      case ModelRole.reasoning:
      case ModelRole.reviewer:
        boost(const ['reason', 'r1', 'o3', 'o4', 'deepseek', 'glm', 'qwen'], 6);
        break;
      case ModelRole.vision:
      case ModelRole.ocr:
        boost(const ['vision', '-vl', '/vl', 'gemini', 'pixtral', 'multimodal'], 8);
        break;
      case ModelRole.fast:
        boost(const ['flash', 'mini', 'fast', 'lite'], 7);
        break;
      case ModelRole.research:
      case ModelRole.explainer:
      case ModelRole.general:
        boost(const ['flash', 'qwen', 'glm', 'step', 'gemini', 'deepseek'], 4);
        break;
    }

    if (_looksFree(model)) score += 3;
    return score;
  }

  static bool _containsAny(String text, List<String> needles) =>
      needles.any(text.contains);

  String modelFor(ModelRole role) {
    final candidates = modelCandidates(role);
    return candidates.isEmpty ? '' : candidates.first;
  }

  String reasoningEffortFor(ModelRole role) {
    final override = roleReasoningEffort[role.key]?.trim() ?? '';
    return override.isEmpty ? reasoningEffort.trim() : override;
  }

  bool webEnabledFor(ModelRole role) {
    return roleWebEnabled[role.key] ?? true;
  }

  AiSettings copyWith({
    String? baseUrl,
    String? defaultModel,
    String? fastModel,
    String? codingModel,
    String? debuggingModel,
    String? reasoningModel,
    String? searchModel,
    String? visionModel,
    String? ocrModel,
    String? reviewerModel,
    String? explainerModel,
    Map<String, List<String>>? fallbackModels,
    Map<String, String>? roleReasoningEffort,
    Map<String, bool>? roleWebEnabled,
    int? maxHistoryMessages,
    String? reasoningEffort,
    String? githubClientId,
    bool? preferFreeModels,
    List<String>? availableModels,
  }) {
    return AiSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      defaultModel: defaultModel ?? this.defaultModel,
      fastModel: fastModel ?? this.fastModel,
      codingModel: codingModel ?? this.codingModel,
      debuggingModel: debuggingModel ?? this.debuggingModel,
      reasoningModel: reasoningModel ?? this.reasoningModel,
      searchModel: searchModel ?? this.searchModel,
      visionModel: visionModel ?? this.visionModel,
      ocrModel: ocrModel ?? this.ocrModel,
      reviewerModel: reviewerModel ?? this.reviewerModel,
      explainerModel: explainerModel ?? this.explainerModel,
      fallbackModels: fallbackModels ?? this.fallbackModels,
      roleReasoningEffort:
          roleReasoningEffort ?? this.roleReasoningEffort,
      roleWebEnabled: roleWebEnabled ?? this.roleWebEnabled,
      maxHistoryMessages: maxHistoryMessages ?? this.maxHistoryMessages,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      githubClientId: githubClientId ?? this.githubClientId,
      preferFreeModels: preferFreeModels ?? this.preferFreeModels,
      availableModels: availableModels ?? this.availableModels,
    );
  }

  static bool _looksFree(String id) {
    final value = id.toLowerCase();
    return value.contains(':free') ||
        value.contains('/free') ||
        value.contains('free-');
  }
}

class AppearanceSettings {
  const AppearanceSettings({
    required this.amoled,
  });

  final bool amoled;
}

final ValueNotifier<bool> gradientAmoledMode = ValueNotifier<bool>(false);

class AppSettingsStore {
  AppSettingsStore({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _secure = secureStorage;

  static const _apiKeyKey = 'ai_api_key_v1';
  static const _githubTokenKey = 'github_token_v1';
  static const _cachedModelsKey = 'ai_cached_models_v1';
  static const _fallbackModelsKey = 'ai_fallback_models_v2';
  static const _roleReasoningKey = 'ai_role_reasoning_v1';
  static const _roleWebKey = 'ai_role_web_v1';
  static const _historyLimitKey = 'ai_history_limit_v1';
  static const _amoledKey = 'appearance_amoled_v1';

  final FlutterSecureStorage _secure;

  Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fallbackModels = _decodeFallbackModels(
      prefs.getString(_fallbackModelsKey),
    );
    final roleReasoning = _decodeStringMap(
      prefs.getString(_roleReasoningKey),
    );
    final roleWebEnabled = _decodeBoolMap(
      prefs.getString(_roleWebKey),
    );
    final availableModels = _decodeModelList(
      prefs.getString(_cachedModelsKey),
    );

    return AiSettings(
      baseUrl:
          prefs.getString('ai_base_url') ?? 'https://openrouter.ai/api/v1',
      defaultModel: prefs.getString('ai_default_model') ?? '',
      fastModel: prefs.getString('ai_fast_model') ?? '',
      codingModel: prefs.getString('ai_coding_model') ?? '',
      debuggingModel: prefs.getString('ai_debugging_model') ?? '',
      reasoningModel: prefs.getString('ai_reasoning_model') ?? '',
      searchModel: prefs.getString('ai_search_model') ?? '',
      visionModel: prefs.getString('ai_vision_model') ?? '',
      ocrModel: prefs.getString('ai_ocr_model') ?? '',
      reviewerModel: prefs.getString('ai_reviewer_model') ?? '',
      explainerModel: prefs.getString('ai_explainer_model') ?? '',
      fallbackModels: fallbackModels,
      roleReasoningEffort: roleReasoning,
      roleWebEnabled: roleWebEnabled,
      maxHistoryMessages:
          (prefs.getInt(_historyLimitKey) ?? 20).clamp(4, 80),
      reasoningEffort: prefs.getString('ai_reasoning_effort') ?? '',
      githubClientId: prefs.getString('github_client_id') ?? '',
      preferFreeModels: prefs.getBool('ai_prefer_free_models') ?? true,
      availableModels: availableModels,
    );
  }

  Future<void> save(AiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('ai_base_url', settings.baseUrl.trim()),
      prefs.setString('ai_default_model', settings.defaultModel.trim()),
      prefs.setString('ai_fast_model', settings.fastModel.trim()),
      prefs.setString('ai_coding_model', settings.codingModel.trim()),
      prefs.setString('ai_debugging_model', settings.debuggingModel.trim()),
      prefs.setString('ai_reasoning_model', settings.reasoningModel.trim()),
      prefs.setString('ai_search_model', settings.searchModel.trim()),
      prefs.setString('ai_vision_model', settings.visionModel.trim()),
      prefs.setString('ai_ocr_model', settings.ocrModel.trim()),
      prefs.setString('ai_reviewer_model', settings.reviewerModel.trim()),
      prefs.setString('ai_explainer_model', settings.explainerModel.trim()),
      prefs.setString(
        _fallbackModelsKey,
        jsonEncode(settings.fallbackModels),
      ),
      prefs.setString(
        _roleReasoningKey,
        jsonEncode(settings.roleReasoningEffort),
      ),
      prefs.setString(
        _roleWebKey,
        jsonEncode(settings.roleWebEnabled),
      ),
      prefs.setInt(_historyLimitKey, settings.maxHistoryMessages),
      prefs.setString('ai_reasoning_effort', settings.reasoningEffort.trim()),
      prefs.setString('github_client_id', settings.githubClientId.trim()),
      prefs.setBool('ai_prefer_free_models', settings.preferFreeModels),
    ]);
  }

  Future<AppearanceSettings> loadAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    final amoled = prefs.getBool(_amoledKey) ?? false;
    gradientAmoledMode.value = amoled;
    return AppearanceSettings(amoled: amoled);
  }

  Future<void> setAmoled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_amoledKey, value);
    gradientAmoledMode.value = value;
  }

  Future<List<String>> cachedModels() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedModelsKey);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCachedModels(Iterable<String> models) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = models
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await prefs.setString(_cachedModelsKey, jsonEncode(normalized));
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
  List<String> _decodeModelList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, List<String>> _decodeFallbackModels(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value is List
              ? (entry.value as List)
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false)
              : const <String>[],
      };
    } catch (_) {
      return const {};
    }
  }

  Map<String, String> _decodeStringMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } catch (_) {
      return const {};
    }
  }

  Map<String, bool> _decodeBoolMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value == true,
      };
    } catch (_) {
      return const {};
    }
  }

}
