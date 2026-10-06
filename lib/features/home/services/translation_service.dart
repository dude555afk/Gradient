import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/retry_policy.dart';
import '../../../core/services/api/stream/stream_chunk.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../settings/widgets/language_select_sheet.dart';

// Upstream comment translated to English.
enum TranslationResultType {
  // Upstream comment translated to English.
  success,

  // Upstream comment translated to English.
  cleared,

  // Upstream comment translated to English.
  cancelled,

  // Upstream comment translated to English.
  noModelConfigured,

  // Upstream comment translated to English.
  error,
}

// Upstream comment translated to English.
class TranslationResult {
  TranslationResult({required this.type, this.errorMessage});

  final TranslationResultType type;
  final String? errorMessage;

  bool get isSuccess => type == TranslationResultType.success;
  bool get isCleared => type == TranslationResultType.cleared;
  bool get isCancelled => type == TranslationResultType.cancelled;
}

/// True when [runToken] is still the in-flight translation for this message.
@visibleForTesting
bool translationRunIsCurrent(Object runToken, Object? currentToken) =>
    identical(currentToken, runToken);

@visibleForTesting
String translationRequestId(String messageId) => 'translate-msg-$messageId';

/// Replaces any in-flight run so the old token no longer owns UI/DB writes.
@visibleForTesting
Object supersedeTranslationRun(Map<String, Object> runs, String messageId) {
  final token = Object();
  runs[messageId] = token;
  return token;
}

/// True when a failed translation should clear UI/DB and report an error.
@visibleForTesting
bool shouldApplyTranslationFailure({
  required Object runToken,
  required Object? currentToken,
  required Object error,
}) {
  if (!translationRunIsCurrent(runToken, currentToken)) return false;
  return !isUserCancelError(error);
}

// Upstream comment translated to English.
///
// Upstream comment translated to English.
// Upstream comment translated to English.
// Upstream comment translated to English.
// Upstream comment translated to English.
// Upstream comment translated to English.
class TranslationService {
  TranslationService({required this.chatService, required this._getContext});

  final ChatService chatService;
  final BuildContext Function() _getContext;
  final Map<String, Object> _runs = <String, Object>{};

  // Upstream comment translated to English.
  ///
  // Upstream comment translated to English.
  // Upstream comment translated to English.
  // Upstream comment translated to English.
  // Upstream comment translated to English.
  ///
  // Upstream comment translated to English.
  Future<TranslationResult> translateMessage({
    required ChatMessage message,
    required void Function() onTranslationStarted,
    required void Function(String translation) onTranslationUpdate,
    required void Function() onTranslationCleared,
  }) async {
    // Resolve a fresh context per call to avoid holding on to a stale BuildContext.
    final context = _getContext();
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;

    // Upstream comment translated to English.
    final language = await showLanguageSelector(context);
    if (language == null) {
      return TranslationResult(type: TranslationResultType.cancelled);
    }

    // Upstream comment translated to English.
    if (language.code == '__clear__') {
      final clearToken = supersedeTranslationRun(_runs, message.id);
      ChatApiService.cancelRequest(translationRequestId(message.id));
      onTranslationCleared();
      await chatService.updateMessage(message.id, translation: '');
      if (identical(_runs[message.id], clearToken)) {
        _runs.remove(message.id);
      }
      return TranslationResult(type: TranslationResultType.cleared);
    }

    // Upstream comment translated to English.
    final translateProvider =
        settings.translateModelProvider ??
        assistant?.chatModelProvider ??
        settings.currentModelProvider;
    final translateModelId =
        settings.translateModelId ??
        assistant?.chatModelId ??
        settings.currentModelId;

    if (translateProvider == null || translateModelId == null) {
      return TranslationResult(type: TranslationResultType.noModelConfigured);
    }

    // Upstream comment translated to English.
    onTranslationStarted();

    // Upstream comment translated to English.
    String textToTranslate = message.content;
    final runToken = Object();
    _runs[message.id] = runToken;

    try {
      // Upstream comment translated to English.
      String prompt = settings.translatePrompt
          .replaceAll('{source_text}', textToTranslate)
          .replaceAll('{target_lang}', language.displayName);

      // Upstream comment translated to English.
      final provider = settings.getProviderConfig(translateProvider);

      final translationStream = ChatApiService.sendMessageStream(
        conversationId: message.conversationId,
        config: provider,
        modelId: translateModelId,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        reasoning: settings.translateGenerationReasoningFor(assistant),
        requestId: translationRequestId(message.id),
        parseMarkdownImageLinks: settings.sendMarkdownImageLinksAsImages,
      );

      final buffer = StringBuffer();

      await for (final chunk in translationStream) {
        if (!translationRunIsCurrent(runToken, _runs[message.id])) {
          return TranslationResult(type: TranslationResultType.cancelled);
        }
        if (chunk is! TextDelta || chunk.text.isEmpty) continue;
        buffer.write(chunk.text);
        // Upstream comment translated to English.
        onTranslationUpdate(buffer.toString());
      }

      if (!translationRunIsCurrent(runToken, _runs[message.id])) {
        return TranslationResult(type: TranslationResultType.cancelled);
      }

      // Upstream comment translated to English.
      await chatService.updateMessage(
        message.id,
        translation: buffer.toString(),
      );

      return TranslationResult(type: TranslationResultType.success);
    } catch (e) {
      if (!shouldApplyTranslationFailure(
        runToken: runToken,
        currentToken: _runs[message.id],
        error: e,
      )) {
        return TranslationResult(type: TranslationResultType.cancelled);
      }
      // Upstream comment translated to English.
      onTranslationCleared();
      await chatService.updateMessage(message.id, translation: '');

      return TranslationResult(
        type: TranslationResultType.error,
        errorMessage: e.toString(),
      );
    } finally {
      if (identical(_runs[message.id], runToken)) {
        _runs.remove(message.id);
      }
    }
  }
}
