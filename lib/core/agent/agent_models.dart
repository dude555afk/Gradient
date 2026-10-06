class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.role,
    required this.content,
  });

  factory AgentMessage.create({
    required String role,
    required String content,
  }) {
    return AgentMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: role,
      content: content,
    );
  }

  final String id;
  final String role;
  final String content;

  AgentMessage copyWith({
    String? id,
    String? role,
    String? content,
  }) {
    return AgentMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
      };

  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim() ?? '';
    return AgentMessage(
      id: rawId.isEmpty
          ? DateTime.now().microsecondsSinceEpoch.toString()
          : rawId,
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
    );
  }
}

class PendingFileChange {
  const PendingFileChange({
    required this.path,
    required this.oldContent,
    required this.newContent,
    required this.currentSha,
    required this.message,
    required this.branch,
  });

  final String path;
  final String oldContent;
  final String newContent;
  final String? currentSha;
  final String message;
  final String branch;

  Map<String, dynamic> toJson() => {
        'path': path,
        'oldContent': oldContent,
        'newContent': newContent,
        'currentSha': currentSha,
        'message': message,
        'branch': branch,
      };

  factory PendingFileChange.fromJson(Map<String, dynamic> json) {
    return PendingFileChange(
      path: json['path']?.toString() ?? '',
      oldContent: json['oldContent']?.toString() ?? '',
      newContent: json['newContent']?.toString() ?? '',
      currentSha: json['currentSha']?.toString(),
      message: json['message']?.toString() ?? '',
      branch: json['branch']?.toString() ?? '',
    );
  }
}

class PendingPullRequest {
  const PendingPullRequest({
    required this.title,
    required this.body,
    required this.head,
    required this.base,
  });

  final String title;
  final String body;
  final String head;
  final String base;

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'head': head,
        'base': base,
      };

  factory PendingPullRequest.fromJson(Map<String, dynamic> json) {
    return PendingPullRequest(
      title: json['title']?.toString() ?? 'Gradient change',
      body: json['body']?.toString() ?? '',
      head: json['head']?.toString() ?? '',
      base: json['base']?.toString() ?? '',
    );
  }
}

class AgentProgressEvent {
  const AgentProgressEvent({
    required this.label,
    this.detail = '',
    this.kind = 'work',
  });

  final String label;
  final String detail;
  final String kind;
}

class AgentResult {
  const AgentResult({
    required this.text,
    required this.fileChanges,
    required this.pullRequests,
    required this.branchUsed,
    required this.model,
  });

  final String text;
  final List<PendingFileChange> fileChanges;
  final List<PendingPullRequest> pullRequests;
  final String? branchUsed;
  final String model;
}
