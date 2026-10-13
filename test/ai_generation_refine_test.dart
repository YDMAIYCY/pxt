import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/knowledge_graph_repository.dart';
import 'package:pxt1/database/models/ai_generation_task_record.dart';
import 'package:pxt1/generator/ai_generation_orchestrator.dart';
import 'package:pxt1/llm/minimax_client.dart';

void main() {
  test(
    'regenerates one AI result using the original result and user feedback',
    () async {
      final client = _CapturingMiniMaxClient();
      final repository = _CapturingAiGenerationRepository();
      final orchestrator = AiGenerationOrchestrator(
        miniMaxClient: client,
        aiGenerationRepository: repository,
        knowledgeGraphRepository: _NoopKnowledgeGraphRepository(),
      );

      final result = await orchestrator.regenerateWithFeedback(
        documentId: 7,
        ocrText: '一次函数讲义 OCR 文本',
        taskType: AiTaskType.mindmapText,
        currentResultText: '一次函数\n- 定义',
        feedback: '太简洁了，请展开每个分支并补充易错点',
      );

      expect(result.success, isTrue);
      expect(client.lastUserPrompt, contains('一次函数讲义 OCR 文本'));
      expect(client.lastUserPrompt, contains('一次函数\n- 定义'));
      expect(client.lastUserPrompt, contains('太简洁了，请展开每个分支并补充易错点'));
      expect(repository.replacedMindmapText, '一次函数\n- 定义域\n- 图像\n- 易错点');
    },
  );
}

class _NoopKnowledgeGraphRepository extends KnowledgeGraphRepository {
  @override
  Future<({int? libraryId, int userId})?> findDocumentScope(
    int documentId,
  ) async {
    return null;
  }
}

class _CapturingMiniMaxClient extends MiniMaxClient {
  _CapturingMiniMaxClient() : super(apiKey: 'test-key');

  String? lastUserPrompt;

  @override
  Future<Map<String, dynamic>> generateStructuredJson({
    required String systemPrompt,
    required String userPrompt,
    Map<String, dynamic>? jsonSchema,
    List<({String base64, String mimeType})>? images,
  }) async {
    lastUserPrompt = userPrompt;
    return {'mindmap_text': '一次函数\n- 定义域\n- 图像\n- 易错点'};
  }
}

class _CapturingAiGenerationRepository extends AiGenerationRepository {
  String? replacedMindmapText;

  @override
  Future<AiGenerationTaskRecord> markTaskRunning({
    required int documentId,
    required String taskType,
    required String inputText,
    String? promptTemplate,
    String provider = 'MiniMax-2.7',
  }) async {
    return AiGenerationTaskRecord(
      id: 1,
      documentId: documentId,
      taskType: taskType,
      inputText: inputText,
      promptTemplate: promptTemplate,
      status: AiTaskStatus.running,
      provider: provider,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  @override
  Future<void> markTaskCompleted({
    required int taskId,
    required String resultText,
  }) async {}

  @override
  Future<void> replaceMindmapText({
    required int documentId,
    required String mindmapText,
  }) async {
    replacedMindmapText = mindmapText;
  }
}
