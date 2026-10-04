class GitHubRepository {
  const GitHubRepository({
    required this.fullName,
    required this.name,
    required this.private,
    required this.defaultBranch,
    required this.description,
  });

  final String fullName;
  final String name;
  final bool private;
  final String defaultBranch;
  final String description;

  factory GitHubRepository.fromJson(Map<String, dynamic> json) {
    return GitHubRepository(
      fullName: json['full_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      private: json['private'] as bool? ?? false,
      defaultBranch: json['default_branch'] as String? ?? 'main',
      description: json['description'] as String? ?? '',
    );
  }
}

class GitHubEntry {
  const GitHubEntry({
    required this.name,
    required this.path,
    required this.type,
    required this.sha,
    required this.size,
  });

  final String name;
  final String path;
  final String type;
  final String sha;
  final int size;

  factory GitHubEntry.fromJson(Map<String, dynamic> json) {
    return GitHubEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      type: json['type'] as String? ?? '',
      sha: json['sha'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type,
        'sha': sha,
        'size': size,
      };
}

class GitHubWorkflowRun {
  const GitHubWorkflowRun({
    required this.id,
    required this.name,
    required this.status,
    required this.conclusion,
    required this.branch,
    required this.url,
  });

  final int id;
  final String name;
  final String status;
  final String conclusion;
  final String branch;
  final String url;

  factory GitHubWorkflowRun.fromJson(Map<String, dynamic> json) {
    return GitHubWorkflowRun(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? '',
      conclusion: json['conclusion'] as String? ?? '',
      branch: json['head_branch'] as String? ?? '',
      url: json['html_url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'conclusion': conclusion,
        'branch': branch,
        'url': url,
      };
}

class GitHubWorkflowJob {
  const GitHubWorkflowJob({
    required this.id,
    required this.name,
    required this.status,
    required this.conclusion,
  });

  final int id;
  final String name;
  final String status;
  final String conclusion;

  factory GitHubWorkflowJob.fromJson(Map<String, dynamic> json) {
    return GitHubWorkflowJob(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? '',
      conclusion: json['conclusion'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'conclusion': conclusion,
      };
}
