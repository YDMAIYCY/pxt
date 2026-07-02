import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/models/ai_result_records.dart';

void main() {
  group('Stage 12 review metadata', () {
    test('database version and training table are registered', () {
      expect(AppDatabase.databaseVersion, 14);
      expect(
        AppDatabase.tableWrongQuestionTrainings,
        'wrong_question_trainings',
      );
      expect(AppDatabase.tableAiChatSessions, 'ai_chat_sessions');
      expect(AppDatabase.tableAiChatMessages, 'ai_chat_messages');
      expect(AppDatabase.tableKnowledgeConcepts, 'knowledge_concepts');
      expect(AppDatabase.tableKnowledgeConceptLinks, 'knowledge_concept_links');
    });

    test('practice question reads spaced review metadata', () {
      final nextReviewAt = DateTime.utc(2026, 4, 29, 8, 30);
      final record = PracticeQuestionRecord.fromMap({
        'id': 1,
        'document_id': 2,
        'question_text': 'question',
        'answer_text': 'answer',
        'analysis_text': 'analysis',
        'difficulty': 'medium',
        'review_status': PracticeQuestionReviewStatus.wrong,
        'last_user_answer': 'user answer',
        'last_reviewed_at': '2026-04-28T08:30:00.000Z',
        'wrong_count': 3,
        'next_review_at': nextReviewAt.toIso8601String(),
        'mastery_score': 40,
        'review_interval_days': 3,
        'correct_streak': 2,
        'parent_question_id': 9,
        'question_kind': PracticeQuestionKind.similar,
        'created_at': '2026-04-28T08:00:00.000Z',
      });

      expect(record.nextReviewAt, nextReviewAt.toLocal());
      expect(record.masteryScore, 40);
      expect(record.reviewIntervalDays, 3);
      expect(record.correctStreak, 2);
      expect(record.parentQuestionId, 9);
      expect(record.questionKind, PracticeQuestionKind.similar);
      expect(record.isSimilarQuestion, isTrue);
    });

    test('practice question metadata defaults keep legacy rows readable', () {
      final record = PracticeQuestionRecord.fromMap({
        'id': 1,
        'document_id': 2,
        'question_text': 'question',
        'created_at': '2026-04-28T08:00:00.000Z',
      });

      expect(record.nextReviewAt, isNull);
      expect(record.masteryScore, 0);
      expect(record.reviewIntervalDays, 0);
      expect(record.correctStreak, 0);
      expect(record.parentQuestionId, isNull);
      expect(record.questionKind, PracticeQuestionKind.normal);
      expect(record.isSimilarQuestion, isFalse);
    });
  });
}
