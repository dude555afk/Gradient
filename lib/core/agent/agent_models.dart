class AgentMessage {
  const AgentMessage({required this.role, required this.content});

  final String role;
  final String content;
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
