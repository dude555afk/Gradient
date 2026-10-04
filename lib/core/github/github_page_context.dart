class GitHubPageContext {
  const GitHubPageContext({
    required this.url,
    required this.owner,
    required this.repo,
    required this.kind,
    this.branch,
    this.number,
    this.filePath,
  });

  final String url;
  final String? owner;
  final String? repo;
  final String kind;
  final String? branch;
  final int? number;
  final String? filePath;

  String? get fullName =>
      owner == null || repo == null ? null : '$owner/$repo';

  bool get hasRepository => fullName != null;

  factory GitHubPageContext.parse(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.host != 'github.com') {
      return GitHubPageContext(
        url: rawUrl,
        owner: null,
        repo: null,
        kind: 'external',
      );
    }

    final parts = uri.pathSegments;
    const reserved = {
      'login',
      'signup',
      'join',
      'settings',
      'notifications',
      'marketplace',
      'explore',
      'topics',
      'search',
      'codespaces',
      'organizations',
      'orgs',
      'users',
    };

    if (parts.length < 2 || reserved.contains(parts.first)) {
      return GitHubPageContext(
        url: rawUrl,
        owner: null,
        repo: null,
        kind: 'github',
      );
    }

    final owner = parts[0];
    final repo = parts[1];

    String kind = 'repo';
    String? branch;
    String? filePath;
    int? number;

    if (parts.length >= 3) {
      switch (parts[2]) {
        case 'pull':
          kind = 'pull_request';
          if (parts.length >= 4) number = int.tryParse(parts[3]);
          break;
        case 'issues':
          kind = 'issue';
          if (parts.length >= 4) number = int.tryParse(parts[3]);
          break;
        case 'actions':
          kind = 'actions';
          break;
        case 'blob':
          kind = 'file';
          if (parts.length >= 4) branch = parts[3];
          if (parts.length >= 5) {
            filePath = parts.sublist(4).join('/');
          }
          break;
        case 'tree':
          kind = 'tree';
          if (parts.length >= 4) branch = parts[3];
          if (parts.length >= 5) {
            filePath = parts.sublist(4).join('/');
          }
          break;
        case 'commit':
          kind = 'commit';
          break;
        case 'commits':
          kind = 'commits';
          break;
        case 'releases':
          kind = 'releases';
          break;
      }
    }

    return GitHubPageContext(
      url: rawUrl,
      owner: owner,
      repo: repo,
      kind: kind,
      branch: branch,
      number: number,
      filePath: filePath,
    );
  }

  String describe() {
    final name = fullName;
    if (name == null) return 'GitHub page: $url';

    final details = <String>[
      'Repository: $name',
      'Page type: $kind',
      if (branch != null) 'Branch/ref: $branch',
      if (number != null) 'Number: $number',
      if (filePath != null) 'Path: $filePath',
      'URL: $url',
    ];
    return details.join('\n');
  }

  bool get mayContainSensitiveFile {
    final path = filePath?.toLowerCase() ?? '';
    if (path.isEmpty) return false;
    return path.endsWith('.env') ||
        path.contains('/.env') ||
        path.endsWith('.pem') ||
        path.endsWith('.key') ||
        path.endsWith('.keystore') ||
        path.endsWith('.jks') ||
        path.contains('credentials') ||
        path.contains('secrets');
  }
}
