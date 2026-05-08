import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/generator/wrong_question_training_service.dart';

void main() {
  group('WrongQuestionTrainingService', () {
    test(
      'parses cause tags and similar questions from structured response',
      () {
        final draft = WrongQuestionTrainingService.parseTrainingResponse({
          'cause_tags': ['概念不清', '审题错误', ''],
          'similar_questions': [
            {
              'question_text': '相似题 1',
              'answer_text': '答案 1',
              'analysis_text': '解析 1',
              'difficulty': 'medium',
            },
            {'question': '相似题 2', 'answer': '答案 2', 'analysis': '解析 2'},
          ],
        });

        expect(draft.causeTags, ['概念不清', '审题错误']);
        expect(draft.similarQuestions, hasLength(2));
        expect(draft.similarQuestions.first['question_text'], '相似题 1');
        expect(draft.similarQuestions.last['answer_text'], '答案 2');
      },
    );

    test('rejects training response without similar questions', () {
      expect(
        () => WrongQuestionTrainingService.parseTrainingResponse({
          'cause_tags': ['计算失误'],
          'similar_questions': [],
        }),
        throwsFormatException,
      );
    });
  });
}
