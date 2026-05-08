import '../database/models/ai_result_records.dart';

class ReviewScheduleUpdate {
  const ReviewScheduleUpdate({
    required this.reviewStatus,
    required this.nextReviewAt,
    required this.masteryScore,
    required this.reviewIntervalDays,
    required this.correctStreak,
    required this.wrongCount,
  });

  final String reviewStatus;
  final DateTime nextReviewAt;
  final int masteryScore;
  final int reviewIntervalDays;
  final int correctStreak;
  final int wrongCount;
}

class ReviewSchedulePolicy {
  const ReviewSchedulePolicy._();

  static const int masteryStep = 20;
  static const int masteredThreshold = 80;

  static ReviewScheduleUpdate forWrongAnswer({
    required PracticeQuestionRecord question,
    required DateTime now,
  }) {
    final wrongCount = question.wrongCount + 1;
    final retryMinutes = (Duration.minutesPerDay / (wrongCount + 1)).round();
    final delay = Duration(minutes: retryMinutes < 10 ? 10 : retryMinutes);

    return ReviewScheduleUpdate(
      reviewStatus: PracticeQuestionReviewStatus.wrong,
      nextReviewAt: now.toUtc().add(delay),
      masteryScore: _clampScore(question.masteryScore - masteryStep),
      reviewIntervalDays: 0,
      correctStreak: 0,
      wrongCount: wrongCount,
    );
  }

  static ReviewScheduleUpdate forCorrectAnswer({
    required PracticeQuestionRecord question,
    required DateTime now,
  }) {
    final masteryScore = _clampScore(question.masteryScore + masteryStep);
    final correctStreak = question.correctStreak + 1;
    final intervalDays = _intervalForStreak(correctStreak, masteryScore);
    final reviewStatus = masteryScore >= masteredThreshold
        ? PracticeQuestionReviewStatus.mastered
        : PracticeQuestionReviewStatus.pending;

    return ReviewScheduleUpdate(
      reviewStatus: reviewStatus,
      nextReviewAt: now.toUtc().add(Duration(days: intervalDays)),
      masteryScore: masteryScore,
      reviewIntervalDays: intervalDays,
      correctStreak: correctStreak,
      wrongCount: question.wrongCount,
    );
  }

  static ReviewScheduleUpdate forManualRetry({
    required PracticeQuestionRecord question,
    required DateTime now,
  }) {
    return ReviewScheduleUpdate(
      reviewStatus: PracticeQuestionReviewStatus.pending,
      nextReviewAt: now.toUtc(),
      masteryScore: question.masteryScore,
      reviewIntervalDays: question.reviewIntervalDays,
      correctStreak: question.correctStreak,
      wrongCount: question.wrongCount,
    );
  }

  static int _intervalForStreak(int correctStreak, int masteryScore) {
    if (masteryScore >= 100 || correctStreak >= 5) {
      return 30;
    }
    if (correctStreak >= 4) {
      return 14;
    }
    if (correctStreak >= 3) {
      return 7;
    }
    if (correctStreak >= 2) {
      return 3;
    }
    return 1;
  }

  static int _clampScore(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 100) {
      return 100;
    }
    return value;
  }
}
