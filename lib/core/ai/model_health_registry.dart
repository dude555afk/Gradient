class ModelHealthRegistry {
  ModelHealthRegistry._();

  static final ModelHealthRegistry instance = ModelHealthRegistry._();

  final Map<String, DateTime> _cooldownUntil = <String, DateTime>{};
  final Map<String, int> _failureStreak = <String, int>{};

  bool isHealthy(String model) {
    final until = _cooldownUntil[model];
    if (until == null) return true;
    if (DateTime.now().isAfter(until)) {
      _cooldownUntil.remove(model);
      _failureStreak.remove(model);
      return true;
    }
    return false;
  }

  Duration? cooldownRemaining(String model) {
    final until = _cooldownUntil[model];
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative) return null;
    return remaining;
  }

  void markSuccess(String model) {
    _failureStreak.remove(model);
    _cooldownUntil.remove(model);
  }

  void markFailure(
    String model, {
    required int statusCode,
  }) {
    final streak = (_failureStreak[model] ?? 0) + 1;
    _failureStreak[model] = streak;

    final baseSeconds = switch (statusCode) {
      429 => 30,
      529 => 20,
      500 || 502 || 503 || 504 => 12,
      _ => 8,
    };

    final multiplier = streak.clamp(1, 4);
    _cooldownUntil[model] = DateTime.now().add(
      Duration(seconds: baseSeconds * multiplier),
    );
  }

  List<String> healthyFirst(Iterable<String> models) {
    final unique = <String>[];
    final seen = <String>{};
    for (final raw in models) {
      final model = raw.trim();
      if (model.isEmpty || !seen.add(model)) continue;
      unique.add(model);
    }

    final healthy = unique.where(isHealthy).toList(growable: false);
    if (healthy.isNotEmpty) return healthy;
    return unique;
  }
}
