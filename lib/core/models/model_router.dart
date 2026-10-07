enum ModelRole {
  general('General'),
  fast('Fast'),
  coding('Coding'),
  debugging('Debugging'),
  reasoning('Reasoning'),
  research('Research'),
  vision('Vision'),
  ocr('OCR'),
  reviewer('Reviewer'),
  explainer('Explainer');

  const ModelRole(this.label);

  final String label;

  String get key => name;
}

class ModelRouter {
  const ModelRouter();

  ModelRole select(
    String task, {
    bool hasImages = false,
  }) {
    final text = task.toLowerCase();

    if (hasImages) {
      if (_containsAny(text, [
        'ocr',
        'extract text',
        'read text',
        'transcribe',
        'what does this say',
        'copy text',
      ])) {
        return ModelRole.ocr;
      }
      return ModelRole.vision;
    }

    if (_containsAny(text, [
      'ocr',
      'extract text from image',
      'read text from image',
      'transcribe screenshot',
    ])) {
      return ModelRole.ocr;
    }

    if (_containsAny(text, [
      'screenshot',
      'image',
      'visual bug',
      'ui looks',
      'photo',
    ])) {
      return ModelRole.vision;
    }

    if (_containsAny(text, [
      'review',
      'audit',
      'security',
      'regression',
      'code review',
      'vulnerability',
    ])) {
      return ModelRole.reviewer;
    }

    if (_containsAny(text, [
      'workflow',
      'github actions',
      'ci ',
      'crash',
      'stack trace',
      'exception',
      'bug',
      'debug',
      'failing',
      'failed',
      'root cause',
    ])) {
      return ModelRole.debugging;
    }

    if (_containsAny(text, [
      'search',
      'web',
      'docs',
      'documentation',
      'latest',
      'look up',
      'research',
    ])) {
      return ModelRole.research;
    }

    if (_containsAny(text, [
      'architecture',
      'reason',
      'why is',
      'dependency conflict',
      'migration',
      'plan',
      'design',
      'tradeoff',
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
      'create app',
      'build ',
      'change code',
    ])) {
      return ModelRole.coding;
    }

    if (_containsAny(text, [
      'explain',
      'teach',
      'summarize',
      'what is',
      'how does',
      'walk me through',
    ])) {
      return ModelRole.explainer;
    }

    if (_containsAny(text, [
      'title',
      'rename',
      'short answer',
      'quick',
      'tiny',
    ])) {
      return ModelRole.fast;
    }

    return ModelRole.general;
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }
}
