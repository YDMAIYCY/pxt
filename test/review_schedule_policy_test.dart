import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/review/review_schedule_policy.dart';

void main() {
  group('ReviewSchedulePolicy', () {
    final now = DateTime.utc(2026, 4, 29, 9);

    test('wrong answer lowers mastery and schedules sooner as errors grow', () {
      final question = _question(
        wrongCount: 2,
        masteryScore: 60,
        correctStreak: 2,
        reviewIntervalDays: 3,
      );

      final update = ReviewSchedulePolicy.forWrongAnswer(
        question: question,
        now: now,
      );

      expect(update.reviewStatus, PracticeQuestionReviewStatus.wrong);
      expect(update.wrongCount, 3);
      expect(update.masteryScore, 40);
      expect(update.correctStreak, 0);
      expect(update.reviewIntervalDays, 0);
      expect(update.nextReviewAt, now.add(const Duration(hours: 6)));
    });

    test('correct answer raises mastery and grows the review interval', () {
      final question = _question(
        masteryScore: 40,
        correctStreak: 1,
        reviewIntervalDays: 1,
      );

      final update = ReviewSchedulePolicy.forCorrectAnswer(
        question: question,
        now: now,
      );

      expect(update.reviewStatus, PracticeQuestionReviewStatus.pending);
      expect(update.masteryScore, 60);
      expect(update.correctStreak, 2);
      expect(update.reviewIntervalDays, 3);
      expect(update.nextReviewAt, now.add(const Duration(days: 3)));
    });

    test('high mastery answer moves question to mastered with long review', () {
      final question = _question(
        masteryScore: 80,
        correctStreak: 3,
        reviewIntervalDays: 14,
      );

      final update = ReviewSchedulePolicy.forCorrectAnswer(
        question: question,
        now: now,
      );

      expect(update.reviewStatus, PracticeQuestionReviewStatus.mastered);
      expect(update.masteryScore, 100);
      expect(update.correctStreak, 4);
      expect(update.reviewIntervalDays, 30);
      expect(update.nextReviewAt, now.add(const Duration(days: 30)));
    });

    test('reset keeps question reviewable immediately', () {
      final question = _question(
        reviewStatus: PracticeQuestionReviewStatus.wrong,
        masteryScore: 20,
        wrongCount: 2,
      );

      final update = ReviewSchedulePolicy.forManualRetry(
        question: question,
        now: now,
      );

      expect(update.reviewStatus, PracticeQuestionReviewStatus.pending);
      expect(update.wrongCount, 2);
      expect(update.masteryScore, 20);
      expect(update.nextReviewAt, now);
    });
  });
}

PracticeQuestionRecord _question({
  String reviewStatus = PracticeQuestionReviewStatus.pending,
  int wrongCount = 0,
  int masteryScore = 0,
  int correctStreak = 0,
  int reviewIntervalDays = 0,
}) {
  return PracticeQuestionRecord(
    id: 1,
    documentId: 2,
    questionText: 'question',
    answerText: 'answer',
    analysisText: 'analysis',
    difficulty: 'medium',
    reviewStatus: reviewStatus,
    wrongCount: wrongCount,
    masteryScore: masteryScore,
    correctStreak: correctStreak,
    reviewIntervalDays: reviewIntervalDays,
    createdAt: DateTime.utc(2026, 4, 28),
  );
}
