import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/interview/interview_ai_service.dart';
import 'package:pxt1/interview/interview_evidence_service.dart';
import 'package:pxt1/interview/interview_models.dart';
import 'package:pxt1/llm/minimax_client.dart';

void main() {
  final config = LlmProviderConfig(
    id: 1,
    userId: 1,
    provider: LlmProvider.custom,
    apiMode: LlmApiMode.openAiCompatible,
    apiKey: 'k',
    baseUrl: 'https://example.com/v1',
    model: 'm',
    maxTokens: 4096,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  test(
    'questions must cite a real evidence key and drop unknown ones',
    () async {
      final service = InterviewAiService(
        miniMaxClient: _client(
          jsonEncode({
            'questions': [
              {
                'question_text': '有来源的题',
                'evidence_key': 'ocr:1',
                'knowledge_point': '极限',
                'reference_points': ['要点'],
              },
              {
                'question_text': '编造的题',
                'evidence_key': 'ocr:999',
                'knowledge_point': '未知',
                'reference_points': [],
              },
            ],
          }),
        ),
      );
      final drafts = await service.generateQuestions(
        evidence: const [
          InterviewEvidence(
            key: 'ocr:1',
            sourceRecordId: 3,
            sourcePageId: 5,
            title: '函数',
            content: '极限内容',
            sourceKind: 'ocr',
          ),
        ],
        mode: 'basic',
        difficulty: 'easy',
        count: 1,
        config: config,
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.questionText, '有来源的题');
      expect(drafts.single.sourceRecordId, 3);
      expect(drafts.single.sourcePageId, 5);
      expect(drafts.single.sourceKind, 'ocr');
      expect(drafts.single.orderIndex, 0);
    },
  );

  test('all-unresolved questions fail instead of inventing sources', () async {
    final service = InterviewAiService(
      miniMaxClient: _client(
        jsonEncode({
          'questions': [
            {
              'question_text': '无来源',
              'evidence_key': 'nope',
              'reference_points': [],
            },
          ],
        }),
      ),
    );
    await expectLater(
      service.generateQuestions(
        evidence: const [
          InterviewEvidence(
            key: 'ocr:1',
            sourceRecordId: 1,
            sourcePageId: 1,
            title: 't',
            content: 'c',
            sourceKind: 'ocr',
          ),
        ],
        mode: 'basic',
        difficulty: 'easy',
        count: 1,
        config: config,
      ),
      throwsFormatException,
    );
  });

  test(
    'evaluation clamps out-of-range scores and keeps total as the sum',
    () async {
      final service = InterviewAiService(
        miniMaxClient: _client(
          jsonEncode({
            'accuracy_score': 80,
            'completeness_score': -5,
            'logic_score': 15,
            'expression_score': 15,
            'strengths': ['a'],
            'weaknesses': [],
            'suggestions': ['b'],
            'follow_up_text': '',
            'evidence_refs': [1, 2],
          }),
        ),
      );
      final result = await service.evaluateAnswer(
        question: _question,
        userAnswer: '回答',
        config: config,
      );
      expect(result.accuracyScore, 50);
      expect(result.completenessScore, 0);
      expect(result.logicScore, 15);
      expect(result.expressionScore, 15);
      expect(result.totalScore, 80);
      expect(result.followUpText, isNull);
      expect(result.evidenceRefs, [1]);
    },
  );

  test(
    'non-integer score fields fail rather than writing a fake grade',
    () async {
      final service = InterviewAiService(
        miniMaxClient: _client(
          jsonEncode({
            'accuracy_score': '很高',
            'completeness_score': 10,
            'logic_score': 10,
            'expression_score': 10,
            'strengths': [],
            'weaknesses': [],
            'suggestions': [],
          }),
        ),
      );
      await expectLater(
        service.evaluateAnswer(
          question: _question,
          userAnswer: '回答',
          config: config,
        ),
        throwsFormatException,
      );
    },
  );
}

final _question = InterviewQuestion(
  id: 1,
  sessionId: 1,
  questionText: '什么是极限？',
  referencePoints: const ['趋近过程', '函数值趋近'],
  knowledgePoint: '极限定义',
  sourceRecordId: 1,
  sourcePageId: 1,
  evidenceText: '极限是x趋近某值时函数值趋近的值',
  sourceKind: 'ocr',
  orderIndex: 0,
  status: 'pending',
);

MiniMaxClient _client(String content) => MiniMaxClient(
  apiKey: 'k',
  endpoint: Uri.parse('https://example.com/v1/chat/completions'),
  httpClient: MockClient(
    (request) async => http.Response(
      jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {'content': content},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    ),
  ),
);
