enum ModelRole {
  fast('Fast'),
  coding('Coding'),
  reasoning('Reasoning'),
  search('Search'),
  vision('Vision'),
  reviewer('Reviewer');

  const ModelRole(this.label);

  final String label;
}

class ModelRouter {
  const ModelRouter();

  ModelRole select(String task) {
    final text = task.toLowerCase();

    if (_containsAny(text, [
      'screenshot',
      'image',
      'ui looks',
      'visual bug',
    ])) {
      return ModelRole.vision;
    }

    if (_containsAny(text, [
      'review',
      'audit',
      'regression',
      'security',
    ])) {
      return ModelRole.reviewer;
    }

    if (_containsAny(text, [
      'search',
      'docs',
      'documentation',
      'latest api',
    ])) {
      return ModelRole.search;
    }

    if (_containsAny(text, [
      'workflow',
      'ci ',
      'architecture',
      'why is',
      'root cause',
      'dependency conflict',
      'migration',
    ])) {
      return ModelRole.reasoning;
    }

    if (_containsAny(text, [
      'implement',
      'fix',
      'refactor',
      'feature',
      'write code',
      'multi-file',
    ])) {
      return ModelRole.coding;
    }

    return ModelRole.fast;
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }
}
