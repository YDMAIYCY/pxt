import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/ui/pages/wrong_question_page.dart';

void main() {
  testWidgets('wrong question page gates mastery behind similar questions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _FakeAiGenerationRepository(
      training: WrongQuestionTrainingRecord(
        id: 1,
        wrongQuestionId: 1,
        causeTags: const ['概念不清'],
        status: WrongQuestionTrainingStatus.pending,
        createdAt: DateTime(2026),
      ),
      similarQuestions: [
        _question(
          id: 11,
          parentQuestionId: 1,
          reviewStatus: PracticeQuestionReviewStatus.pending,
          questionKind: PracticeQuestionKind.similar,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WrongQuestionPage(
          item: PracticeQuestionWithDocument(
            question: _question(
              id: 1,
              reviewStatus: PracticeQuestionReviewStatus.wrong,
              wrongCount: 2,
            ),
            documentTitle: '函数专题',
          ),
          aiGenerationRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.tap(
      find.byIcon(Icons.check_circle_rounded),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repository.markMasteredCalls, 0);
    expect(find.textContaining('相似题'), findsWidgets);
  });
}

PracticeQuestionRecord _question({
  required int id,
  String reviewStatus = PracticeQuestionReviewStatus.pending,
  int wrongCount = 0,
  int? parentQuestionId,
  String questionKind = PracticeQuestionKind.normal,
}) {
  return PracticeQuestionRecord(
    id: id,
    documentId: 2,
    questionText: '题目 $id',
    answerText: '答案',
    analysisText: '解析',
    difficulty: 'medium',
    reviewStatus: reviewStatus,
    wrongCount: wrongCount,
    parentQuestionId: parentQuestionId,
    questionKind: questionKind,
    createdAt: DateTime(2026),
  );
}

class _FakeAiGenerationRepository extends AiGenerationRepository {
  _FakeAiGenerationRepository({
    required this.training,
    required this.similarQuestions,
  });

  final WrongQuestionTrainingRecord? training;
  final List<PracticeQuestionRecord> similarQuestions;
  int markMasteredCalls = 0;

  @override
  Future<WrongQuestionTrainingRecord?> fetchWrongQuestionTraining(
    int wrongQuestionId,
  ) async {
    return training;
  }

  @override
  Future<List<PracticeQuestionRecord>> fetchSimilarQuestions(
    int parentQuestionId,
  ) async {
    return similarQuestions;
  }

  @override
  Future<bool> markPracticeQuestionMastered(int questionId) async {
    markMasteredCalls++;
    return false;
  }
}
