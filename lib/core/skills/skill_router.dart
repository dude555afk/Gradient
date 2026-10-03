class SkillDefinition {
  const SkillDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.triggers,
  });

  final String id;
  final String name;
  final String description;
  final List<String> triggers;
}

class SkillRouter {
  const SkillRouter();

  static const builtIns = <SkillDefinition>[
    SkillDefinition(
      id: 'github',
      name: 'GitHub',
      description: 'Remote repository, branch, commit, issue and PR work.',
      triggers: [
        'repo',
        'github',
        'branch',
        'commit',
        'pull request',
        'pr ',
        'issue',
      ],
    ),
    SkillDefinition(
      id: 'ci',
      name: 'CI',
      description: 'Diagnose and repair GitHub Actions and build workflows.',
      triggers: [
        'workflow',
        'actions',
        'ci ',
        'build failed',
        'pipeline',
        'release failed',
      ],
    ),
    SkillDefinition(
      id: 'android',
      name: 'Android',
      description: 'Gradle, Kotlin, Compose, manifest, APK and signing work.',
      triggers: [
        'android',
        'gradle',
        'kotlin',
        'compose',
        'apk',
        'manifest',
        'signing',
      ],
    ),
    SkillDefinition(
      id: 'research',
      name: 'Research',
      description: 'Search official docs and verify implementation details.',
      triggers: [
        'search',
        'docs',
        'documentation',
        'api changed',
        'lookup',
      ],
    ),
  ];

  List<SkillDefinition> select(String task) {
    final text = task.toLowerCase();
    final result = builtIns
        .where((skill) => skill.triggers.any(text.contains))
        .toList(growable: false);

    return result.isEmpty
        ? <SkillDefinition>[builtIns.first]
        : result;
  }
}
