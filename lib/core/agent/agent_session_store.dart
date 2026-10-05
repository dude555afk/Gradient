import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'agent_models.dart';

class AgentCheckpoint {
  const AgentCheckpoint({
    required this.id,
    required this.label,
    required this.messages,
    required this.changes,
    required this.pullRequests,
    required this.taskBranch,
    required this.createdAt,
  });

  final String id;
  final String label;
  final List<AgentMessage> messages;
  final List<PendingFileChange> changes;
  final List<PendingPullRequest> pullRequests;
  final String? taskBranch;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'messages': messages.map((e) => e.toJson()).toList(),
        'changes': changes.map((e) => e.toJson()).toList(),
        'pullRequests': pullRequests.map((e) => e.toJson()).toList(),
        'taskBranch': taskBranch,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AgentCheckpoint.fromJson(Map<String, dynamic> json) {
    return AgentCheckpoint(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Checkpoint',
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => AgentMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      changes: (json['changes'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (e) => PendingFileChange.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      pullRequests: (json['pullRequests'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (e) => PendingPullRequest.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      taskBranch: json['taskBranch']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}

class AgentConversation {
  const AgentConversation({
    required this.id,
    required this.repoFullName,
    required this.title,
    required this.messages,
    required this.changes,
    required this.pullRequests,
    required this.checkpoints,
    required this.taskBranch,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String repoFullName;
  final String title;
  final List<AgentMessage> messages;
  final List<PendingFileChange> changes;
  final List<PendingPullRequest> pullRequests;
  final List<AgentCheckpoint> checkpoints;
  final String? taskBranch;
  final DateTime createdAt;
  final DateTime updatedAt;

  AgentConversation copyWith({
    String? title,
    List<AgentMessage>? messages,
    List<PendingFileChange>? changes,
    List<PendingPullRequest>? pullRequests,
    List<AgentCheckpoint>? checkpoints,
    String? taskBranch,
    bool clearTaskBranch = false,
    DateTime? updatedAt,
  }) {
    return AgentConversation(
      id: id,
      repoFullName: repoFullName,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      changes: changes ?? this.changes,
      pullRequests: pullRequests ?? this.pullRequests,
      checkpoints: checkpoints ?? this.checkpoints,
      taskBranch: clearTaskBranch ? null : taskBranch ?? this.taskBranch,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'repoFullName': repoFullName,
        'title': title,
        'messages': messages.map((e) => e.toJson()).toList(),
        'changes': changes.map((e) => e.toJson()).toList(),
        'pullRequests': pullRequests.map((e) => e.toJson()).toList(),
        'checkpoints': checkpoints.map((e) => e.toJson()).toList(),
        'taskBranch': taskBranch,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AgentConversation.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();

    return AgentConversation(
      id: json['id']?.toString() ?? '',
      repoFullName: json['repoFullName']?.toString() ?? '',
      title: json['title']?.toString() ?? 'New chat',
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => AgentMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      changes: (json['changes'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (e) => PendingFileChange.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      pullRequests: (json['pullRequests'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (e) => PendingPullRequest.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      checkpoints: (json['checkpoints'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (e) => AgentCheckpoint.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      taskBranch: json['taskBranch']?.toString(),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }
}

class AgentSessionStore {
  static const _conversationsKey = 'gradient_agent_conversations_v1';
  static const _activeKey = 'gradient_agent_active_v1';

  Future<List<AgentConversation>> list(String repoFullName) async {
    final all = await _loadAll();
    final result = all
        .where((e) => e.repoFullName == repoFullName)
        .toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<AgentConversation> create(
    String repoFullName, {
    List<AgentMessage> seedMessages = const [],
    String? title,
  }) async {
    final now = DateTime.now();
    final conversation = AgentConversation(
      id: now.microsecondsSinceEpoch.toString(),
      repoFullName: repoFullName,
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'New chat',
      messages: List<AgentMessage>.from(seedMessages),
      changes: const [],
      pullRequests: const [],
      checkpoints: const [],
      taskBranch: null,
      createdAt: now,
      updatedAt: now,
    );
    await save(conversation);
    await setActive(repoFullName, conversation.id);
    return conversation;
  }

  Future<AgentConversation?> loadActive(String repoFullName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeKey);
    String? activeId;
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        activeId = map[repoFullName]?.toString();
      } catch (_) {}
    }

    final conversations = await list(repoFullName);
    if (conversations.isEmpty) return null;
    if (activeId == null) return conversations.first;

    for (final conversation in conversations) {
      if (conversation.id == activeId) return conversation;
    }
    return conversations.first;
  }

  Future<void> setActive(String repoFullName, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeKey);
    var map = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    map[repoFullName] = id;
    await prefs.setString(_activeKey, jsonEncode(map));
  }

  Future<void> save(AgentConversation conversation) async {
    final all = await _loadAll();
    final next = <AgentConversation>[];
    var replaced = false;

    for (final item in all) {
      if (item.id == conversation.id) {
        next.add(conversation);
        replaced = true;
      } else {
        next.add(item);
      }
    }
    if (!replaced) next.add(conversation);

    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final capped = next.take(30).toList(growable: false);
    await _saveAll(capped);
  }

  Future<void> delete(String repoFullName, String id) async {
    final all = await _loadAll();
    await _saveAll(all.where((e) => e.id != id).toList(growable: false));

    final active = await loadActive(repoFullName);
    if (active != null) {
      await setActive(repoFullName, active.id);
    }
  }

  Future<AgentConversation> branchFrom(
    AgentConversation source,
    int messageCount,
  ) {
    final count = messageCount.clamp(0, source.messages.length);
    return create(
      source.repoFullName,
      seedMessages: source.messages.take(count).toList(growable: false),
      title: source.title == 'New chat'
          ? 'Branched chat'
          : '${source.title} branch',
    );
  }

  Future<List<AgentConversation>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationsKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (e) => AgentConversation.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((e) => e.id.isNotEmpty && e.repoFullName.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveAll(List<AgentConversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _conversationsKey,
      jsonEncode(conversations.map((e) => e.toJson()).toList()),
    );
  }
}
