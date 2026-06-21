import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/generator/ai_interview_service.dart';

void main() {
  group('AI interview service', () {
    test('parses interview scoring response', () {
      final feedback = AiInterviewService.parseFeedback({
        'score': 82,
        'hit_points': ['定义域'],
        'missing_points': ['对应关系'],
        'misconceptions': ['把函数当成公式'],
        'correction': '注意函数是映射关系。',
        'standard_answer': '函数是从定义域到值域的对应关系。',
        'next_follow_up': '定义域为什么重要？',
      });

      expect(feedback.score, 82);
      expect(feedback.hitPoints, ['定义域']);
      expect(feedback.missingPoints, ['对应关系']);
      expect(feedback.standardAnswer, contains('函数'));
    });
  });
}
