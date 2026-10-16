class ReviewPriorityWeights {
  const ReviewPriorityWeights({
    this.overdue = 30,
    this.errors = 25,
    this.mastery = 25,
    this.recency = 10,
    this.importance = 10,
  });
  final double overdue, errors, mastery, recency, importance;
}

/// Deterministic and independent of UI/model calls. Every input comes from evidence.
class ReviewPriorityPolicy {
  const ReviewPriorityPolicy({this.weights = const ReviewPriorityWeights()});
  final ReviewPriorityWeights weights;

  double score({
    required int mastery,
    required int attempts,
    required int errors,
    required DateTime now,
    DateTime? dueAt,
    DateTime? lastStudiedAt,
    int importance = 1,
  }) {
    final overdueDays = dueAt == null
        ? 0.0
        : now.difference(dueAt).inHours / 24;
    final due = dueAt != null && !dueAt.isAfter(now)
        ? (0.5 + overdueDays / 14).clamp(0.0, 1.0)
        : 0.0;
    final errorRate = attempts == 0 ? 0.0 : (errors / attempts).clamp(0.0, 1.0);
    final age = lastStudiedAt == null
        ? 0.0
        : (now.difference(lastStudiedAt).inHours / (24 * 30)).clamp(0.0, 1.0);
    return weights.overdue * due +
        weights.errors * errorRate +
        weights.mastery * (1 - mastery.clamp(0, 100) / 100) +
        weights.recency * age +
        weights.importance * ((importance.clamp(1, 5) - 1) / 4);
  }
}
