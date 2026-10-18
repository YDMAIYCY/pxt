import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/generator/ai_generation_orchestrator.dart';

void main() {
  group('rich practice questions', () {
    test('normalizes richer question kinds', () {
      expect(
        PracticeQuestionKind.normalize('multiple_choice'),
        PracticeQuestionKind.multipleChoice,
      );
      expect(
        PracticeQuestionKind.normalize('fill_blank'),
        PracticeQuestionKind.fillBlank,
      );
      expect(
        PracticeQuestionKind.normalize('true_false'),
        PracticeQuestionKind.trueFalse,
      );
      expect(
        PracticeQuestionKind.normalize('calculation'),
        PracticeQuestionKind.calculation,
      );
      expect(PracticeQuestionKind.normalize('oral'), PracticeQuestionKind.oral);
    });

    test('practice question model reads options rubric and keywords', () {
      final record = PracticeQuestionRecord.fromMap({
        'id': 1,
        'document_id': 2,
        'question_text': 'Which one is correct?',
        'answer_text': 'B',
        'analysis_text': 'B matches the definition.',
        'difficulty': 'medium',
        'review_status': PracticeQuestionReviewStatus.pending,
        'wrong_count': 0,
        'question_kind': PracticeQuestionKind.multipleChoice,
        'options_json': '["A","B","C"]',
        'rubric_json': '{"definition":40,"example":60}',
        'expected_keywords_json': '["function","domain"]',
        'created_at': '2026-06-17T00:00:00.000Z',
      });

      expect(record.options, ['A', 'B', 'C']);
      expect(record.rubric, {'definition': 40, 'example': 60});
      expect(record.expectedKeywords, ['function', 'domain']);
    });

    test('orchestrator parses rich practice question response', () {
      final questions = AiGenerationOrchestrator.parsePracticeQuestionsForTest({
        'questions': [
          {
            'kind': 'multiple_choice',
            'question_text': '函数定义中必须强调什么？',
            'options': ['定义域', '颜色', '字体'],
            'answer_text': '定义域',
            'analysis_text': '函数必须先明确定义域。',
            'difficulty': 'easy',
            'expected_keywords': ['定义域', '对应关系'],
          },
        ],
      });

      expect(
        questions.single['question_kind'],
        PracticeQuestionKind.multipleChoice,
      );
      expect(questions.single['options_json'], contains('定义域'));
      expect(questions.single['expected_keywords_json'], contains('对应关系'));
    });

    test('orchestrator rejects multiple choice questions without options', () {
      expect(
        () => AiGenerationOrchestrator.parsePracticeQuestionsForTest({
          'questions': [
            {
              'kind': 'multiple_choice',
              'question_text': '下列方程中，是一元一次方程的是？',
              'answer_text': 'C',
              'analysis_text': '选择题必须给出选项才能作答。',
              'difficulty': 'easy',
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
