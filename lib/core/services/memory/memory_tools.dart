import 'dart:convert';

import '../../database/chat_database_repository.dart';
import '../../models/assistant.dart';
import '../../models/memory_entry.dart';
import '../../models/user_profile_field.dart';
import '../chat/chat_service.dart';
import 'memory_block_builder.dart';
import 'memory_prompts.dart';
import 'memory_repository.dart';
import 'memory_smart_add.dart';
import 'memory_tokenizer.dart';
import 'memory_trace.dart';

/// Memory system V1 tool declarations + dispatch (§10).
///
/// Tool descriptions are model contracts (D-18 / §16.2): bilingual constants
/// here, never ARB/l10n. Chosen by [MemoryPromptLang].
abstract final class MemoryTools {
  static bool _englishOnlyMemoryMode(MemoryPromptLang _) => false;

  MemoryTools._();

  static const String memoryRead = 'memory_read';
  static const String memoryUpdate = 'memory_update';
  static const String memorySearchProfile = 'memory_search_profile';
  static const String memoryEdit = 'memory_edit';
  static const String memoryDelete = 'memory_delete';
  static const String updateUserProfile = 'update_user_profile';
  static const String chatSearch = 'chat_search';

  static const Set<String> enableMemoryToolNames = {
    memoryRead,
    memoryUpdate,
    memorySearchProfile,
    memoryEdit,
    memoryDelete,
    updateUserProfile,
  };

  /// Tools that persist something beyond the current conversation.
  static const Set<String> writeToolNames = {
    memoryUpdate,
    memoryEdit,
    memoryDelete,
    updateUserProfile,
  };

  static const Set<String> allToolNames = {
    ...enableMemoryToolNames,
    chatSearch,
  };

  static const List<String> _legacyToolNames = [
    'create_memory',
    'edit_memory',
    'delete_memory',
  ];

  /// Names of the removed legacy tools (§10.11). Exposed for tests.
  static List<String> get legacyToolNames =>
      List<String>.unmodifiable(_legacyToolNames);

  // —— Definitions ——

  /// Build tool definitions gated by [enableMemory] / [allowPastConversationRecall]
  /// (§10.1). [writeScope] controls whether `scope` appears on `memory_update`
  /// (§10.2 / §4.3).
  static List<Map<String, dynamic>> buildDefinitions({
    required MemoryPromptLang lang,
    required MemoryWriteScope writeScope,
    required bool enableMemory,
    required bool allowPastConversationRecall,

    /// False in temporary conversations, where reads stay available but a
    /// write would outlive the conversation the user asked to be throwaway.
    bool allowMemoryWrites = true,
  }) {
    final out = <Map<String, dynamic>>[];
    if (enableMemory) {
      out.add(_defMemoryRead(lang));
      out.add(_defMemorySearchProfile(lang));
      if (allowMemoryWrites) {
        out.add(_defMemoryUpdate(lang, writeScope));
        out.add(_defMemoryEdit(lang));
        out.add(_defMemoryDelete(lang));
        out.add(_defUpdateUserProfile(lang));
      }
    }
    if (allowPastConversationRecall) {
      out.add(_defChatSearch(lang));
    }
    return out;
  }

  /// All seven v2 memory tool schemas, ungated, for the settings catalog.
  ///
  /// `memory_update` is built with [MemoryWriteScope.toolDefaultGlobal] so the
  /// optional `scope` parameter (and its description) is present for editing.
  static List<Map<String, dynamic>> catalogDefinitions(MemoryPromptLang lang) {
    return [
      _defMemoryRead(lang),
      _defMemorySearchProfile(lang),
      _defMemoryUpdate(lang, MemoryWriteScope.toolDefaultGlobal),
      _defMemoryEdit(lang),
      _defMemoryDelete(lang),
      _defUpdateUserProfile(lang),
      _defChatSearch(lang),
    ];
  }

  /// Legacy create/edit/delete_memory tool schemas (pre-v2 memory system).
  ///
  /// Localised by [lang] like [buildDefinitions], so the schemas match the
  /// language the legacy rules are sent in.
  static List<Map<String, dynamic>> legacyDefinitions(MemoryPromptLang lang) {
    final zh = _englishOnlyMemoryMode(lang);
    return [
      {
        'type': 'function',
        'function': {
          'name': 'create_memory',
          'description': zh ? '\u65b0\u589e\u4e00\u6761\u8bb0\u5fc6\u8bb0\u5f55。' : 'Create a memory record.',
          'parameters': {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': zh
                    ? '\u8bb0\u5fc6\u8bb0\u5f55\u7684\u5185\u5bb9。'
                    : 'The content of the memory record.',
              },
            },
            'required': ['content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'edit_memory',
          'description': zh
              ? '\u66f4\u65b0\u4e00\u6761\u5df2\u6709\u7684\u8bb0\u5fc6\u8bb0\u5f55。'
              : 'Update an existing memory record.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': zh
                    ? '\u8bb0\u5fc6\u8bb0\u5f55\u7684 id。'
                    : 'The id of the memory record.',
              },
              'content': {
                'type': 'string',
                'description': zh
                    ? '\u8bb0\u5fc6\u8bb0\u5f55\u7684\u5185\u5bb9。'
                    : 'The content of the memory record.',
              },
            },
            'required': ['id', 'content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'delete_memory',
          'description': zh ? '\u5220\u9664\u4e00\u6761\u8bb0\u5fc6\u8bb0\u5f55。' : 'Delete a memory record.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': zh
                    ? '\u8bb0\u5fc6\u8bb0\u5f55\u7684 id。'
                    : 'The id of the memory record.',
              },
            },
            'required': ['id'],
          },
        },
      },
    ];
  }

  // —— Dispatch ——

  /// Handle a memory / chat_search tool call.
  ///
  /// Returns `null` when the tool is not applicable for this assistant's
  /// gates (so the caller can fall through to other handlers).
  static Future<String?> handle({
    required String name,
    required Map<String, dynamic> args,
    required Assistant assistant,
    required MemoryRepository repository,
    required ChatDatabaseRepository chatRepository,
    ChatService? chatService,
    String? conversationId,
    Future<void> Function()? onMutated,

    /// When provided, `memory_update` goes through real Smart Add (§12.6).
    MemorySmartAdd? smartAdd,
    MemoryPromptLang? promptLang,
    Future<String> Function(String prompt)? memoryLlmCall,
    String? smartAddPromptZh,
    String? smartAddPromptEn,

    /// When provided, the call is recorded as a one-step trace.
    MemoryTraceRecorder? traceRecorder,
    String? conversationTitle,
  }) async {
    // Temporary chats are discarded on exit. Reads stay available, but a
    // recorded trace (title, args, result) would outlive the conversation.
    final temporary =
        chatService?.isTemporaryConversation(conversationId) ?? false;
    final activeRecorder = temporary ? null : traceRecorder;

    if (name == chatSearch) {
      if (!assistant.allowPastConversationRecall) return null;
      final (handle, step) = _beginToolTrace(
        activeRecorder,
        kind: MemoryTraceStepKind.chatSearch,
        name: name,
        args: args,
        assistant: assistant,
        conversationId: conversationId,
        conversationTitle: conversationTitle,
      );
      try {
        final result = await _handleChatSearch(
          args: args,
          chatService: chatService,
          conversationId: conversationId,
          assistantId: assistant.id,
        );
        _finishToolTrace(handle, step, result: result);
        return result;
      } catch (e) {
        final result = toolError(
          error: 'memory_execution_error',
          message: e.toString(),
          tool: name,
          instruction:
              'The memory tool failed. Retry only after correcting the parameters, or inform the user about the issue.',
        );
        _finishToolTrace(handle, step, result: result, error: e.toString());
        return result;
      }
    }

    if (!assistant.enableMemory) return null;
    if (!enableMemoryToolNames.contains(name)) return null;

    // A temporary conversation is discarded when the user leaves it. Reads stay
    // available, but a write would outlive the conversation the user asked to
    // be throwaway.
    if (writeToolNames.contains(name) &&
        (chatService?.isTemporaryConversation(conversationId) ?? false)) {
      return toolError(
        error: 'temporary_conversation',
        message: 'Memory cannot be written from a temporary conversation.',
        tool: name,
        instruction:
            'Do not retry. Tell the user that memory is disabled in temporary '
            'chats, and continue without saving.',
      );
    }

    final (handle, step) = _beginToolTrace(
      activeRecorder,
      kind: MemoryTraceStepKind.memoryTool,
      name: name,
      args: args,
      assistant: assistant,
      conversationId: conversationId,
      conversationTitle: conversationTitle,
    );
    try {
      String? result;
      switch (name) {
        case memoryRead:
          result = await _handleMemoryRead(
            args: args,
            assistant: assistant,
            chatRepository: chatRepository,
          );
        case memoryUpdate:
          result = await _handleMemoryUpdate(
            args: args,
            assistant: assistant,
            repository: repository,
            chatRepository: chatRepository,
            smartAdd: smartAdd,
            promptLang: promptLang,
            memoryLlmCall: memoryLlmCall,
            smartAddPromptZh: smartAddPromptZh,
            smartAddPromptEn: smartAddPromptEn,
            traceStep: step,
          );
          await onMutated?.call();
        case memorySearchProfile:
          result = await _handleMemorySearchProfile(
            args: args,
            assistant: assistant,
            chatRepository: chatRepository,
          );
        case memoryEdit:
          result = await _handleMemoryEdit(
            args: args,
            assistant: assistant,
            repository: repository,
            chatRepository: chatRepository,
            traceStep: step,
          );
          await onMutated?.call();
        case memoryDelete:
          result = await _handleMemoryDelete(
            args: args,
            assistant: assistant,
            repository: repository,
            chatRepository: chatRepository,
            traceStep: step,
          );
          await onMutated?.call();
        case updateUserProfile:
          result = await _handleUpdateUserProfile(
            args: args,
            repository: repository,
            chatRepository: chatRepository,
            traceStep: step,
          );
          await onMutated?.call();
        default:
          result = null;
      }
      if (result == null) {
        handle?.commit(error: 'unsupported_tool');
        return null;
      }
      _finishToolTrace(handle, step, result: result);
      return result;
    } catch (e) {
      final result = toolError(
        error: 'memory_execution_error',
        message: e.toString(),
        tool: name,
        instruction:
            'The memory tool failed. Retry only after correcting the parameters, or inform the user about the issue.',
      );
      _finishToolTrace(handle, step, result: result, error: e.toString());
      return result;
    }
  }

  static (MemoryTraceHandle?, MemoryTraceStep?) _beginToolTrace(
    MemoryTraceRecorder? recorder, {
    required MemoryTraceStepKind kind,
    required String name,
    required Map<String, dynamic> args,
    required Assistant assistant,
    String? conversationId,
    String? conversationTitle,
  }) {
    if (recorder == null) return (null, null);
    try {
      final handle = recorder.begin(
        trigger: MemoryTraceTrigger.toolCall,
        scope: memoryTraceScopeOf(assistant.memoryWriteScope),
        conversationId: conversationId,
        conversationTitle: conversationTitle,
        assistantId: assistant.id,
        assistantName: assistant.name,
      );
      final step = handle?.beginStep(kind, label: name);
      step?.appendPrompt(_prettyJson(args));
      return (handle, step);
    } catch (_) {
      return (null, null);
    }
  }

  static void _finishToolTrace(
    MemoryTraceHandle? handle,
    MemoryTraceStep? step, {
    required String result,
    String? error,
  }) {
    if (handle == null) return;
    step?.appendResponse(result);
    step?.finish(
      error == null
          ? MemoryTraceStepStatus.success
          : MemoryTraceStepStatus.failed,
      error: error,
    );
    handle.commit(error: error);
  }

  static String _prettyJson(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value?.toString() ?? '';
    }
  }

  static String toolError({
    required String error,
    required String message,
    required String tool,
    String? instruction,
  }) {
    return jsonEncode({
      'type': 'tool_error',
      'error': error,
      'message': message,
      'tool': tool,
      if (instruction != null) 'instruction': instruction,
    });
  }

  /// Resolve write [MemoryScope] from assistant policy + optional tool arg.
  static MemoryScope resolveWriteScope(
    MemoryWriteScope policy,
    String? scopeArg,
  ) {
    switch (policy) {
      case MemoryWriteScope.alwaysGlobal:
        return MemoryScope.global;
      case MemoryWriteScope.alwaysAssistant:
        return MemoryScope.assistant;
      case MemoryWriteScope.toolDefaultGlobal:
        if (scopeArg == 'assistant') return MemoryScope.assistant;
        return MemoryScope.global;
      case MemoryWriteScope.toolDefaultAssistant:
        if (scopeArg == 'global') return MemoryScope.global;
        return MemoryScope.assistant;
    }
  }

  /// Whitespace-split, lowercase, then [MemoryTokenizer.escapeLike] (§5.9).
  static List<String> searchTokens(String query) {
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map(MemoryTokenizer.escapeLike)
        .toList(growable: false);
  }

  // —— Handlers ——

  static Future<String> _handleMemoryRead({
    required Map<String, dynamic> args,
    required Assistant assistant,
    required ChatDatabaseRepository chatRepository,
  }) async {
    final type = _parseMemoryType(args['type']);
    if (args.containsKey('type') && args['type'] != null && type == null) {
      return toolError(
        error: 'invalid_memory_type',
        message: 'type must be one of: identity, workflow, voice, instruction.',
        tool: memoryRead,
      );
    }
    final includeArchived = _asBool(args['include_archived']) ?? false;
    final limit = (_asInt(args['limit']) ?? 50).clamp(1, 100);
    final offset = int.tryParse((args['offset'] ?? 0).toString());
    if (offset == null || offset < 0) {
      return toolError(
        error: 'invalid_memory_offset',
        message: 'offset must be a non-negative integer.',
        tool: memoryRead,
      );
    }

    final all = await chatRepository.queryVisibleMemories(
      assistantId: assistant.id,
      type: type,
      includeArchived: includeArchived,
    );
    final start = offset.clamp(0, all.length);
    final end = start + limit.clamp(0, all.length - start);
    final returned = all.sublist(start, end);
    final hasMore = end < all.length;
    return jsonEncode({
      'total': all.length,
      'returned': returned.length,
      'offset': offset,
      'limit': limit,
      'has_more': hasMore,
      'next_offset': hasMore ? end : null,
      'entries': [
        for (final e in returned) _entrySummary(e, includeStatus: true),
      ],
    });
  }

  static Future<String> _handleMemoryUpdate({
    required Map<String, dynamic> args,
    required Assistant assistant,
    required MemoryRepository repository,
    required ChatDatabaseRepository chatRepository,
    MemorySmartAdd? smartAdd,
    MemoryPromptLang? promptLang,
    Future<String> Function(String prompt)? memoryLlmCall,
    String? smartAddPromptZh,
    String? smartAddPromptEn,
    MemoryTraceStep? traceStep,
  }) async {
    final type = _parseMemoryType(args['type']);
    if (type == null) {
      return toolError(
        error: 'invalid_memory_type',
        message:
            'type is required and must be one of: identity, workflow, voice, instruction.',
        tool: memoryUpdate,
      );
    }
    final content = (args['content'] ?? '').toString();
    if (content.trim().isEmpty) {
      return toolError(
        error: 'invalid_memory_content',
        message: 'Memory content must not be empty.',
        tool: memoryUpdate,
      );
    }

    final scopeArg = args['scope']?.toString();
    final scope = resolveWriteScope(assistant.memoryWriteScope, scopeArg);
    final assistantId = scope == MemoryScope.assistant ? assistant.id : null;

    // Real Smart Add when wired (§12.6); else exact-duplicate → SKIP / NEW.
    final adder =
        smartAdd ??
        MemorySmartAdd(repository: repository, chatRepository: chatRepository);
    final result = await adder.addOne(
      item: SmartAddItem(
        type: type,
        content: content,
        scope: scope,
        assistantId: assistantId,
      ),
      visibilityAssistantId: assistant.id,
      source: MemorySource.tool,
      lang: promptLang ?? MemoryPromptLang.en,
      llmCall: memoryLlmCall,
      overrideZh: smartAddPromptZh,
      overrideEn: smartAddPromptEn,
      traceStep: traceStep,
    );
    traceStep?.setParsedJson(result.toToolJson());
    return jsonEncode(result.toToolJson());
  }

  static Future<String> _handleMemorySearchProfile({
    required Map<String, dynamic> args,
    required Assistant assistant,
    required ChatDatabaseRepository chatRepository,
  }) async {
    final query = (args['query'] ?? '').toString();
    if (query.trim().isEmpty) {
      return toolError(
        error: 'invalid_query',
        message: 'query must not be empty.',
        tool: memorySearchProfile,
      );
    }
    final type = _parseMemoryType(args['type']);
    if (args.containsKey('type') && args['type'] != null && type == null) {
      return toolError(
        error: 'invalid_memory_type',
        message: 'type must be one of: identity, workflow, voice, instruction.',
        tool: memorySearchProfile,
      );
    }
    final limit = (_asInt(args['limit']) ?? 10).clamp(1, 20);
    final tokens = searchTokens(query);
    if (tokens.isEmpty) {
      return jsonEncode({
        'query': query,
        'matched': <Map<String, dynamic>>[],
        'related': <Map<String, dynamic>>[],
      });
    }

    final matched = await chatRepository.searchMemories(
      assistantId: assistant.id,
      tokens: tokens,
      type: type,
      matchAll: true,
      limit: limit,
    );

    final matchedIds = {for (final e in matched) e.id};
    // relatedId → first via matched id (matched order).
    final viaByRelated = <String, String>{};
    for (final m in matched) {
      for (final rid in m.relatedIds) {
        if (matchedIds.contains(rid)) continue;
        viaByRelated.putIfAbsent(rid, () => m.id);
      }
    }

    final relatedEntries = await chatRepository.memoriesByIds(
      viaByRelated.keys.toList(growable: false),
    );
    final relatedFiltered = relatedEntries
        .where(
          (e) =>
              e.status == MemoryStatus.active &&
              _isVisible(e, assistant.id) &&
              !matchedIds.contains(e.id),
        )
        .toList();
    relatedFiltered.sort((a, b) {
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) return byUpdated;
      return a.id.compareTo(b.id);
    });
    final relatedCapped = relatedFiltered.length <= 10
        ? relatedFiltered
        : relatedFiltered.sublist(0, 10);

    return jsonEncode({
      'query': query,
      'matched': [
        for (final e in matched) _entrySummary(e, includeStatus: false),
      ],
      'related': [
        for (final e in relatedCapped)
          {
            'id': e.id,
            'viaId': viaByRelated[e.id],
            'type': MemoryEntry.typeToString(e.type),
            'content': e.content,
            'updatedAt': MemoryBlockBuilder.fmtDate(e.updatedAt),
          },
      ],
    });
  }

  static Future<String> _handleMemoryEdit({
    required Map<String, dynamic> args,
    required Assistant assistant,
    required MemoryRepository repository,
    required ChatDatabaseRepository chatRepository,
    MemoryTraceStep? traceStep,
  }) async {
    final id = (args['id'] ?? '').toString().trim();
    final content = (args['content'] ?? '').toString();
    if (id.isEmpty) {
      return toolError(
        error: 'invalid_memory_id',
        message: 'id is required (e.g. mem_a1b2c3d4).',
        tool: memoryEdit,
      );
    }
    if (content.trim().isEmpty) {
      return toolError(
        error: 'invalid_memory_content',
        message: 'Memory content must not be empty.',
        tool: memoryEdit,
      );
    }

    final found = await chatRepository.memoriesByIds([id]);
    final entry = found.isEmpty ? null : found.first;
    if (entry == null ||
        entry.status != MemoryStatus.active ||
        !_isVisible(entry, assistant.id)) {
      return toolError(
        error: 'memory_not_found',
        message: 'No active visible memory was found for id $id.',
        tool: memoryEdit,
        instruction:
            'Use memory_read or memory_search_profile to obtain a valid id, or call memory_update to write a new entry instead of editing a missing one.',
      );
    }

    final updated = await repository.updateContent(id, content);
    if (updated == null) {
      return toolError(
        error: 'memory_not_found',
        message: 'No active visible memory was found for id $id.',
        tool: memoryEdit,
        instruction:
            'Use memory_read or memory_search_profile to obtain a valid id, or call memory_update to write a new entry instead of editing a missing one.',
      );
    }
    traceStep?.addMutation(
      MemoryTraceMutation(
        kind: MemoryTraceMutationKind.memoryEdited,
        targetId: updated.id,
        label: MemoryEntry.typeToString(updated.type),
        before: entry.content,
        after: updated.content,
      ),
    );
    return jsonEncode({
      'action': 'EDIT',
      'id': updated.id,
      'content': updated.content,
    });
  }

  static Future<String> _handleMemoryDelete({
    required Map<String, dynamic> args,
    required Assistant assistant,
    required MemoryRepository repository,
    required ChatDatabaseRepository chatRepository,
    MemoryTraceStep? traceStep,
  }) async {
    final id = (args['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      return toolError(
        error: 'invalid_memory_id',
        message: 'id is required (e.g. mem_a1b2c3d4).',
        tool: memoryDelete,
      );
    }

    final found = await chatRepository.memoriesByIds([id]);
    final entry = found.isEmpty ? null : found.first;
    if (entry == null || !_isVisible(entry, assistant.id)) {
      return toolError(
        error: 'memory_not_found',
        message: 'No visible memory was found for id $id.',
        tool: memoryDelete,
        instruction:
            'Use memory_read or memory_search_profile to obtain a valid id, or skip archiving a missing memory.',
      );
    }

    final ok = await repository.archive(id);
    if (!ok) {
      return toolError(
        error: 'memory_not_found',
        message: 'No visible memory was found for id $id.',
        tool: memoryDelete,
        instruction:
            'Use memory_read or memory_search_profile to obtain a valid id, or skip archiving a missing memory.',
      );
    }
    traceStep?.addMutation(
      MemoryTraceMutation(
        kind: MemoryTraceMutationKind.memoryArchived,
        targetId: id,
        label: MemoryEntry.typeToString(entry.type),
        before: entry.content,
      ),
    );
    return jsonEncode({'action': 'ARCHIVE', 'id': id});
  }

  static Future<String> _handleUpdateUserProfile({
    required Map<String, dynamic> args,
    required MemoryRepository repository,
    required ChatDatabaseRepository chatRepository,
    MemoryTraceStep? traceStep,
  }) async {
    final rawFields = args['fields'];
    if (rawFields is! List) {
      return toolError(
        error: 'invalid_profile_fields',
        message: 'fields must be an array of {key, value} objects.',
        tool: updateUserProfile,
      );
    }

    final updated = <String>[];
    final cleared = <String>[];
    final rejected = <Map<String, String>>[];

    // Only read prior values when a trace needs before/after.
    final priorValues = <String, String>{};
    if (traceStep != null) {
      try {
        for (final field in await chatRepository.readProfileFields()) {
          priorValues[field.key] = field.value;
        }
      } catch (_) {}
    }

    for (final item in rawFields) {
      if (item is! Map) {
        rejected.add({'key': '', 'reason': 'invalid_item'});
        continue;
      }
      final map = item.cast<String, dynamic>();
      final key = (map['key'] ?? '').toString();
      final value = (map['value'] ?? '').toString();
      if (!UserProfileField.isValidKey(key)) {
        rejected.add({'key': key, 'reason': 'unknown_key'});
        continue;
      }
      if (value.trim().isEmpty) {
        await repository.removeProfileField(key);
        cleared.add(key);
        traceStep?.addMutation(
          MemoryTraceMutation(
            kind: MemoryTraceMutationKind.profileFieldCleared,
            targetId: key,
            before: priorValues[key],
          ),
        );
      } else {
        await repository.putProfileField(key, value, MemorySource.tool);
        updated.add(key);
        traceStep?.addMutation(
          MemoryTraceMutation(
            kind: MemoryTraceMutationKind.profileFieldWritten,
            targetId: key,
            before: priorValues[key],
            after: value,
          ),
        );
      }
    }

    return jsonEncode({
      'action': 'PROFILE_UPDATE',
      'updated': updated,
      'cleared': cleared,
      'rejected': rejected,
    });
  }

  static Future<String> _handleChatSearch({
    required Map<String, dynamic> args,
    required ChatService? chatService,
    required String? conversationId,
    required String assistantId,
  }) async {
    final query = (args['query'] ?? '').toString();
    if (query.trim().isEmpty) {
      return toolError(
        error: 'invalid_query',
        message: 'query must not be empty.',
        tool: chatSearch,
      );
    }
    if (chatService == null) {
      return toolError(
        error: 'chat_search_unavailable',
        message: 'Chat search service is unavailable.',
        tool: chatSearch,
      );
    }
    final limit = (_asInt(args['limit']) ?? 10).clamp(1, 20);
    final filterConversationId = args['conversation_id']?.toString().trim();
    final tokens = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return jsonEncode({'query': query, 'results': <Map<String, dynamic>>[]});
    }

    final scoped =
        filterConversationId != null && filterConversationId.isNotEmpty;
    final matches = await chatService.searchConversationMatches(
      tokens: tokens,
      limit: limit * 8,
      conversationId: scoped ? filterConversationId : null,
      excludeConversationId: scoped ? null : conversationId,
      assistantId: assistantId,
    );

    final results = <Map<String, dynamic>>[];
    for (final m in matches) {
      final role = m.messageRole;
      if (role != 'user' && role != 'assistant') continue;
      final content = (m.messageContent ?? '').trim();
      if (content.isEmpty) continue;

      final conv = chatService.getConversation(m.conversationId);
      final summary = conv?.summary?.trim();
      results.add({
        'conversationId': m.conversationId,
        'title': m.conversationTitle,
        if (summary != null && summary.isNotEmpty) 'summary': summary,
        'role': role,
        'date': MemoryBlockBuilder.fmtDate(m.updatedAt),
        'snippet': _snippet(content, tokens),
      });
      if (results.length >= limit) break;
    }

    return jsonEncode({'query': query, 'results': results});
  }

  // —— Schema builders ——

  static Map<String, dynamic> _defMemoryRead(MemoryPromptLang lang) {
    final zh = _englishOnlyMemoryMode(lang);
    return {
      'type': 'function',
      'function': {
        'name': memoryRead,
        'description': zh
            ? '\u8bfb\u53d6\u7528\u6237\u7684\u957f\u671f\u8bb0\u5fc6。type \u53ef\u9009：identity（\u59d3\u540d、\u8eab\u8fb9\u7684\u4eba、\u804c\u4e1a\u7b49\u8eab\u4efd\u4fe1\u606f）、workflow（\u505a\u4e8b\u65b9\u5f0f、\u5de5\u5177\u504f\u597d、\u8c03\u8bd5\u4e60\u60ef）、voice（\u884c\u6587\u98ce\u683c、\u53e5\u5f0f\u8282\u594f、\u7528\u8bcd\u4e60\u60ef）、instruction（\u7528\u6237\u5bf9\u4f60\u7684\u660e\u786e\u8981\u6c42）。\u4e0d\u4f20 type \u5219\u8fd4\u56de\u5168\u90e8\u7c7b\u578b。\u4f7f\u7528 limit \u548c offset \u5206\u9875；\u7ed3\u679c\u4e2d total \u4e3a\u7b5b\u9009\u540e\u7684\u603b\u6761\u6570，has_more \u4e3a true \u65f6，\u4fdd\u6301\u7b5b\u9009\u6761\u4ef6\u4e0d\u53d8，\u5c06 next_offset \u4f5c\u4e3a\u4e0b\u6b21\u8c03\u7528\u7684 offset \u7ee7\u7eed\u8bfb\u53d6，\u6700\u540e\u4e00\u9875 next_offset \u4e3a null。\u5bf9\u8bdd\u4e2d\u5df2\u7ecf\u63d0\u4f9b\u4e86\u8bb0\u5fc6\u6458\u8981，\u53ea\u6709\u5728\u6458\u8981\u6807\u4e86 mode="summary" \u88ab\u622a\u65ad、\u6216\u9700\u8981\u62ff\u5230\u6761\u76ee id \u65f6\u624d\u9700\u8981\u8c03\u7528。'
            : 'Read the user\'s long-term memory. Optional type: identity (name, people around them, occupation, etc.), workflow (ways of working, tool preferences, debugging habits), voice (writing style, rhythm, word choice), instruction (explicit requests to you). Omit type to return all types. Paginate with limit and offset. The result total counts all entries matching the filters. When has_more is true, keep the same filters and pass next_offset as offset to read the next page; next_offset is null on the last page. A memory summary is already in the conversation; call this only when a block is marked mode="summary" (truncated) or you need entry ids.',
        'parameters': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': ['identity', 'workflow', 'voice', 'instruction'],
              'description': zh
                  ? '\u53ea\u8fd4\u56de\u8be5\u7c7b\u578b\u7684\u8bb0\u5fc6。\u7701\u7565\u5219\u8fd4\u56de\u5168\u90e8\u7c7b\u578b。'
                  : 'Return only memories of this type. Omit to return all types.',
            },
            'include_archived': {
              'type': 'boolean',
              'description': zh
                  ? '\u662f\u5426\u5305\u542b\u5df2\u5f52\u6863\u7684\u8bb0\u5fc6。\u9ed8\u8ba4 false。'
                  : 'Whether to include archived memories. Default false.',
            },
            'limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 100,
              'description': zh
                  ? '\u6bcf\u9875\u6700\u591a\u8fd4\u56de\u591a\u5c11\u6761，\u9ed8\u8ba4 50，\u6700\u5927 100。'
                  : 'Maximum entries per page. Default 50, maximum 100.',
            },
            'offset': {
              'type': 'integer',
              'minimum': 0,
              'description': zh
                  ? '\u8df3\u8fc7\u7b5b\u9009\u7ed3\u679c\u7684\u6761\u6570，\u9ed8\u8ba4 0。\u4ece\u4e0a\u4e00\u9875\u7684 next_offset \u7ee7\u7eed\u8bfb\u53d6。'
                  : 'Number of matching entries to skip. Default 0. Use next_offset from the previous page to continue.',
            },
          },
          'required': <String>[],
        },
      },
    };
  }

  static Map<String, dynamic> _defMemoryUpdate(
    MemoryPromptLang lang,
    MemoryWriteScope writeScope,
  ) {
    final zh = _englishOnlyMemoryMode(lang);
    final properties = <String, dynamic>{
      'type': {
        'type': 'string',
        'enum': ['identity', 'workflow', 'voice', 'instruction'],
        'description': zh
            ? 'identity \u8eab\u4efd\u4fe1\u606f；workflow \u505a\u4e8b\u65b9\u5f0f\u4e0e\u5de5\u5177\u504f\u597d；voice \u8868\u8fbe\u98ce\u683c；instruction \u7528\u6237\u5bf9\u4f60\u7684\u660e\u786e\u8981\u6c42。'
            : 'identity: identity facts; workflow: ways of working and tool preferences; voice: expression style; instruction: explicit requests to you.',
      },
      'content': {
        'type': 'string',
        'description': zh
            ? '\u4e00\u6761\u5b8c\u6574、\u81ea\u5305\u542b\u7684\u7b2c\u4e09\u4eba\u79f0\u9648\u8ff0\u53e5，\u4f8b\u5982「\u7528\u6237\u504f\u597d\u76f4\u63a5、\u53ef\u843d\u5730\u7684\u4e2d\u6587\u8bf4\u660e」。\u4e0d\u8981\u4f7f\u7528「\u8fd9\u4e2a」「\u521a\u624d」\u7b49\u6307\u56de\u672c\u6b21\u5bf9\u8bdd\u7684\u8bcd。'
            : 'One complete, self-contained third-person statement, e.g. "The user prefers direct, actionable explanations in Chinese." Avoid deictic words that refer back to this conversation.',
      },
    };
    if (writeScope == MemoryWriteScope.toolDefaultGlobal ||
        writeScope == MemoryWriteScope.toolDefaultAssistant) {
      properties['scope'] = {
        'type': 'string',
        'enum': ['global', 'assistant'],
        'description': zh
            ? 'global \u5bf9\u6240\u6709\u52a9\u624b\u53ef\u89c1；assistant \u53ea\u5bf9\u5f53\u524d\u52a9\u624b\u53ef\u89c1。\u7701\u7565\u65f6\u6309\u7528\u6237\u8bbe\u7f6e\u7684\u9ed8\u8ba4\u503c。'
            : 'global is visible to all assistants; assistant is visible only to the current assistant. When omitted, uses the user\'s configured default.',
      };
    }
    return {
      'type': 'function',
      'function': {
        'name': memoryUpdate,
        'description': zh
            ? '\u5199\u5165\u4e00\u6761\u7528\u6237\u957f\u671f\u8bb0\u5fc6。\u7cfb\u7edf\u4f1a\u81ea\u52a8\u4e0e\u5df2\u6709\u8bb0\u5fc6\u53bb\u91cd\u5408\u5e76，\u4e0d\u9700\u8981\u5148\u8bfb\u53d6\u518d\u5168\u6587\u66ff\u6362。\u53ea\u5199\u4e0b\u6b21\u65b0\u5f00\u5bf9\u8bdd\u65f6\u4ecd\u7136\u6210\u7acb\u7684\u7a33\u5b9a\u4fe1\u606f；\u672c\u6b21\u5bf9\u8bdd\u5185\u7684\u4e34\u65f6\u4e0a\u4e0b\u6587\u4e0d\u8981\u5199。'
            : 'Write one long-term user memory. The system deduplicates and merges with existing memories automatically; you do not need to read then replace. Only write stable facts that will still hold in a future conversation; do not write ephemeral context from this chat.',
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': ['type', 'content'],
        },
      },
    };
  }

  static Map<String, dynamic> _defMemorySearchProfile(MemoryPromptLang lang) {
    final zh = _englishOnlyMemoryMode(lang);
    return {
      'type': 'function',
      'function': {
        'name': memorySearchProfile,
        'description': zh
            ? '\u641c\u7d22\u7528\u6237\u7684\u957f\u671f\u8bb0\u5fc6。\u5f53\u5bf9\u8bdd\u4e2d\u63d0\u4f9b\u7684\u8bb0\u5fc6\u6458\u8981\u4e0d\u591f\u8be6\u7ec6、\u88ab\u622a\u65ad（\u6807\u4e86 mode="summary"），\u6216\u9700\u8981\u67e5\u627e\u67d0\u4e2a\u7279\u5b9a\u4fe1\u606f\u65f6\u4f7f\u7528。\u6309\u5173\u952e\u8bcd\u5339\u914d，\u591a\u4e2a\u5173\u952e\u8bcd\u4e4b\u95f4\u662f「\u4e14」\u5173\u7cfb。'
            : 'Search the user\'s long-term memory. Use when the in-conversation memory summary is incomplete, truncated (mode="summary"), or you need a specific fact. Keyword match; multiple keywords are ANDed.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': zh
                  ? '\u5173\u952e\u8bcd，\u591a\u4e2a\u7528\u7a7a\u683c\u5206\u9694。\u4e2d\u6587\u53ef\u4ee5\u76f4\u63a5\u5199\u8fde\u7eed\u77ed\u8bed。'
                  : 'Keywords separated by spaces. Continuous Chinese phrases can be used as-is.',
            },
            'type': {
              'type': 'string',
              'enum': ['identity', 'workflow', 'voice', 'instruction'],
              'description': zh
                  ? '\u53ea\u5728\u8be5\u7c7b\u578b\u5185\u641c\u7d22。\u7701\u7565\u5219\u641c\u7d22\u5168\u90e8\u7c7b\u578b。'
                  : 'Search only within this type. Omit to search all types.',
            },
            'limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 20,
              'description': zh
                  ? '\u6700\u591a\u8fd4\u56de\u591a\u5c11\u6761，\u9ed8\u8ba4 10。'
                  : 'Maximum number of entries to return. Default 10.',
            },
          },
          'required': ['query'],
        },
      },
    };
  }

  static Map<String, dynamic> _defMemoryEdit(MemoryPromptLang lang) {
    final zh = _englishOnlyMemoryMode(lang);
    return {
      'type': 'function',
      'function': {
        'name': memoryEdit,
        'description': zh
            ? '\u4fee\u6539\u4e00\u6761\u5df2\u6709\u8bb0\u5fc6\u7684\u5185\u5bb9。\u9700\u8981\u5148\u7528 memory_read \u6216 memory_search_profile \u62ff\u5230\u6761\u76ee id（\u5f62\u5982 mem_xxxxxxxx）。\u53ea\u5728\u8bb0\u5fc6\u5185\u5bb9\u786e\u5b9e\u8fc7\u65f6\u6216\u6709\u9519\u65f6\u4f7f\u7528；\u8865\u5145\u65b0\u4fe1\u606f\u8bf7\u7528 memory_update。'
            : 'Edit the content of an existing memory. First obtain the entry id (e.g. mem_xxxxxxxx) via memory_read or memory_search_profile. Use only when content is outdated or wrong; for new information use memory_update.',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {
              'type': 'string',
              'description': zh
                  ? '\u6761\u76ee id，\u5f62\u5982 mem_a1b2c3d4。'
                  : 'Entry id, e.g. mem_a1b2c3d4.',
            },
            'content': {
              'type': 'string',
              'description': zh
                  ? '\u4fee\u6539\u540e\u7684\u5b8c\u6574\u5185\u5bb9，\u4f1a\u6574\u4f53\u66ff\u6362\u539f\u5185\u5bb9。'
                  : 'The full replacement content.',
            },
          },
          'required': ['id', 'content'],
        },
      },
    };
  }

  static Map<String, dynamic> _defMemoryDelete(MemoryPromptLang lang) {
    final zh = _englishOnlyMemoryMode(lang);
    return {
      'type': 'function',
      'function': {
        'name': memoryDelete,
        'description': zh
            ? '\u5f52\u6863\u4e00\u6761\u8bb0\u5fc6（\u8f6f\u5220\u9664）。\u5f52\u6863\u540e\u4e0d\u518d\u51fa\u73b0\u5728\u8bb0\u5fc6\u6458\u8981\u548c\u641c\u7d22\u7ed3\u679c\u91cc，\u7528\u6237\u4ecd\u53ef\u4ee5\u5728\u8bbe\u7f6e\u4e2d\u770b\u5230\u5e76\u6062\u590d。\u9700\u8981\u5148\u7528 memory_read \u6216 memory_search_profile \u62ff\u5230\u6761\u76ee id。\u53ea\u5728\u7528\u6237\u660e\u786e\u8868\u793a\u67d0\u6761\u8bb0\u5fc6\u4e0d\u518d\u6210\u7acb\u65f6\u4f7f\u7528。'
            : 'Archive a memory (soft delete). Archived entries disappear from the memory summary and search results, but the user can still see and restore them in settings. First obtain the entry id via memory_read or memory_search_profile. Use only when the user clearly says a memory no longer holds.',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {
              'type': 'string',
              'description': zh
                  ? '\u6761\u76ee id，\u5f62\u5982 mem_a1b2c3d4。'
                  : 'Entry id, e.g. mem_a1b2c3d4.',
            },
          },
          'required': ['id'],
        },
      },
    };
  }

  static Map<String, dynamic> _defUpdateUserProfile(MemoryPromptLang lang) {
    final zh = _englishOnlyMemoryMode(lang);
    return {
      'type': 'function',
      'function': {
        'name': updateUserProfile,
        'description': zh
            ? '\u66f4\u65b0\u7528\u6237\u753b\u50cf\u5b57\u6bb5。\u8fd9\u4e9b\u662f\u6700\u7a33\u5b9a\u7684\u8eab\u4efd\u4fe1\u606f。\u4e0d\u786e\u5b9a\u7684\u65f6\u5019\u4e0d\u8981\u5199。'
            : 'Update user profile fields. These are the most stable identity facts. Do not write when uncertain.',
        'parameters': {
          'type': 'object',
          'properties': {
            'fields': {
              'type': 'array',
              'description': zh ? '\u8981\u66f4\u65b0\u7684\u5b57\u6bb5\u5217\u8868。' : 'List of fields to update.',
              'items': {
                'type': 'object',
                'properties': {
                  'key': {
                    'type': 'string',
                    'description': zh
                        ? '\u53ef\u7528\u5b57\u6bb5：preferred_name（\u7528\u6237\u5e0c\u671b\u4f60\u600e\u4e48\u79f0\u547c\u4ed6）、gender、pronouns、preferred_language、timezone、occupation、location。\u5176\u4ed6\u7a33\u5b9a\u5b57\u6bb5\u7528 custom.<\u540d\u79f0>，\u540d\u79f0\u53ea\u80fd\u662f\u5b57\u6bcd、\u6570\u5b57、\u4e0b\u5212\u7ebf\u6216\u8fde\u5b57\u7b26。'
                        : 'Allowed keys: preferred_name (how the user wants to be addressed), gender, pronouns, preferred_language, timezone, occupation, location. Other stable fields use custom.<name> where name is letters, digits, underscore, or hyphen only.',
                  },
                  'value': {
                    'type': 'string',
                    'description': zh
                        ? '\u5b57\u6bb5\u53d6\u503c。\u4f20\u7a7a\u5b57\u7b26\u4e32\u8868\u793a\u6e05\u9664\u8be5\u5b57\u6bb5。'
                        : 'Field value. An empty string clears the field.',
                  },
                },
                'required': ['key', 'value'],
              },
            },
          },
          'required': ['fields'],
        },
      },
    };
  }

  static Map<String, dynamic> _defChatSearch(MemoryPromptLang lang) {
    final zh = _englishOnlyMemoryMode(lang);
    return {
      'type': 'function',
      'function': {
        'name': chatSearch,
        'description': zh
            ? '\u5728\u5386\u53f2\u5bf9\u8bdd\u4e2d\u6309\u5173\u952e\u8bcd\u641c\u7d22\u6d88\u606f\u5185\u5bb9（\u4ec5\u5f53\u524d\u52a9\u624b\u7684\u4f1a\u8bdd，\u4ee5\u53ca\u6ca1\u6709\u5f52\u5c5e\u52a9\u624b\u7684\u65e7\u4f1a\u8bdd）。\u9700\u8981\u56de\u5fc6\u4e4b\u524d\u804a\u8fc7\u4ec0\u4e48，\u6216\u8005\u7528\u6237\u63d0\u5230「\u4e0a\u6b21」「\u4e4b\u524d\u8bf4\u7684」「\u6211\u4eec\u8ba8\u8bba\u8fc7」\u65f6，\u4f18\u5148\u4f7f\u7528\u8fd9\u4e2a\u5de5\u5177。\u9ed8\u8ba4\u4e0d\u641c\u7d22\u5f53\u524d\u5bf9\u8bdd，\u56e0\u4e3a\u5f53\u524d\u5bf9\u8bdd\u7684\u5185\u5bb9\u5df2\u7ecf\u5728\u4e0a\u4e0b\u6587\u91cc。'
            : 'Search message content in this assistant\'s past conversations (and unowned older chats) by keywords. Prefer this when recalling prior discussion, or when the user mentions "last time", "earlier", or "we discussed". By default the current conversation is excluded because it is already in context.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': zh
                  ? '\u5173\u952e\u8bcd，\u591a\u4e2a\u7528\u7a7a\u683c\u5206\u9694。'
                  : 'Keywords separated by spaces.',
            },
            'limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 20,
              'description': zh
                  ? '\u6700\u591a\u8fd4\u56de\u591a\u5c11\u6761，\u9ed8\u8ba4 10。'
                  : 'Maximum number of results. Default 10.',
            },
            'conversation_id': {
              'type': 'string',
              'description': zh
                  ? '\u53ea\u5728\u6307\u5b9a\u4f1a\u8bdd\u5185\u641c\u7d22。\u7701\u7565\u5219\u641c\u7d22\u9664\u5f53\u524d\u4f1a\u8bdd\u5916、\u5f53\u524d\u52a9\u624b\u53ef\u89c1\u7684\u4f1a\u8bdd。'
                  : 'Search only within this conversation. Omit to search this assistant\'s visible conversations except the current one.',
            },
          },
          'required': ['query'],
        },
      },
    };
  }

  // —— Helpers ——

  static Map<String, dynamic> _entrySummary(
    MemoryEntry e, {
    required bool includeStatus,
  }) {
    return {
      'id': e.id,
      'type': MemoryEntry.typeToString(e.type),
      'scope': MemoryEntry.scopeToString(e.scope),
      if (includeStatus) 'status': MemoryEntry.statusToString(e.status),
      'content': e.content,
      'updatedAt': MemoryBlockBuilder.fmtDate(e.updatedAt),
    };
  }

  static bool _isVisible(MemoryEntry entry, String assistantId) {
    if (entry.scope == MemoryScope.global) return true;
    return entry.assistantId == assistantId;
  }

  static MemoryType? _parseMemoryType(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    try {
      return MemoryEntry.typeFromString(s);
    } catch (_) {
      return null;
    }
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _snippet(String content, List<String> tokens) {
    final lower = content.toLowerCase();
    var idx = -1;
    var hitLen = 0;
    for (final t in tokens) {
      final i = lower.indexOf(t);
      if (i >= 0) {
        idx = i;
        hitLen = t.length;
        break;
      }
    }
    const radius = 40;
    if (idx < 0) {
      final cut = content.length <= 80 ? content : content.substring(0, 80);
      return '……$cut……';
    }
    final start = (idx - radius).clamp(0, content.length);
    final end = (idx + hitLen + radius).clamp(0, content.length);
    var snip = content.substring(start, end);
    if (start > 0) snip = '……$snip';
    if (end < content.length) snip = '$snip……';
    return snip;
  }
}
