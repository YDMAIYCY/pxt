import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/models/ai_chat_records.dart';
import 'package:pxt1/database/models/knowledge_context_source.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/generator/ai_chat_service.dart';
import 'package:pxt1/llm/minimax_client.dart';

void main() {
  group('knowledge-grounded AI chat', () {
    test(
      'database exposes repository methods for local knowledge retrieval',
      () {
        final source = File(
          'lib/database/knowledge_context_repository.dart',
        ).readAsStringSync();

        expect(source, contains('Future<List<KnowledgeContextSource>> search'));
        expect(source, contains('tableOcrTexts'));
        expect(source, contains('tableKnowledgeCards'));
        expect(source, contains('tableReviewOutlines'));
        expect(source, contains('tablePracticeQuestions'));
        expect(source, contains('tableKnowledgeConcepts'));
        expect(source, contains('tableKnowledgeConceptLinks'));
        expect(source, contains('KnowledgeContextSourceType.knowledgeGraph'));
      },
    );

    test('adaptive graph hooks update mastery from practice outcomes', () {
      final graphSource = File(
        'lib/database/knowledge_graph_repository.dart',
      ).readAsStringSync();
      final practiceSource = File(
        'lib/database/practice_session_repository.dart',
      ).readAsStringSync();

      // Next-best-action suggestions are still derived by the graph repository.
      expect(graphSource, contains('Future<List<KnowledgeNextBestAction>>'));
      expect(graphSource, contains('prerequisite'));

      // Mastery is updated from practice outcomes by the evidence-based
      // summariser in the practice session repository. The behaviour itself is
      // exercised end-to-end in learning_task_repository_test.dart.
      expect(practiceSource, contains('class MasteryEvidence'));
      expect(practiceSource, contains("'mastery_score'"));
      expect(practiceSource, contains("'weakness_score'"));
    });

    test(
      'chat service injects retrieved sources into the model prompt',
      () async {
        final client = _CapturingMiniMaxClient();
        final service = AiChatService(miniMaxClient: client);

        final reply = await service.generateReply(
          config: _testConfig,
          messages: [
            AiChatMessageRecord(
              id: 1,
              sessionId: 1,
              role: AiChatMessageRole.user,
              content: '函数单调性怎么判断？',
              createdAt: DateTime.utc(2026, 6, 16),
            ),
          ],
          contextSources: const [
            KnowledgeContextSource(
              documentId: 12,
              documentTitle: '高数讲义第3页',
              sourceType: KnowledgeContextSourceType.knowledgeCard,
              sourceLabel: '知识卡片',
              title: '函数单调性',
              snippet: '若 f(x) 在区间内可导，f’(x)>0 时函数递增。',
            ),
          ],
        );

        expect(reply, 'grounded reply');
        expect(client.systemPrompt, contains('根据用户提供的真实知识库证据回答'));
        expect(client.messages.single['content'], contains('"citation":1'));
        expect(client.messages.single['content'], contains('高数讲义第3页'));
        expect(client.messages.single['content'], contains('函数单调性怎么判断？'));
      },
    );
  });
}

final _testDate = DateTime.utc(2026, 6, 16);

final _testConfig = LlmProviderConfig(
  id: 1,
  userId: 7,
  provider: LlmProvider.minimax,
  apiMode: LlmApiMode.tokenPlan,
  apiKey: 'sk-cp-test-key',
  baseUrl: '',
  model: 'MiniMax-M2.7',
  maxTokens: 4096,
  createdAt: _testDate,
  updatedAt: _testDate,
);

class _CapturingMiniMaxClient extends MiniMaxClient {
  String systemPrompt = '';
  List<Map<String, String>> messages = const [];

  @override
  Future<String> generateChatReply({
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) async {
    this.systemPrompt = systemPrompt;
    this.messages = messages;
    return 'grounded reply';
  }
}
