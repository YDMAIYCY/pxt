import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/ai_generation_task_record.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/ocr_text_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/database/ocr_text_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/generator/ai_generation_orchestrator.dart';
import 'package:pxt1/ui/pages/ai_generation_page.dart';

void main() {
  testWidgets('single generation clears loading state after an exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiGenerationPage(
          documentId: 1,
          authRepository: _FakeAuthRepository(),
          sourceDocumentRepository: _FakeSourceDocumentRepository(),
          ocrTextRepository: _FakeOcrTextRepository(),
          aiGenerationRepository: _EmptyAiGenerationRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          aiGenerationOrchestrator: _ThrowingAiGenerationOrchestrator(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
  });

  testWidgets('practice question results render multiple choice options', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiGenerationPage(
          documentId: 1,
          authRepository: _FakeAuthRepository(),
          sourceDocumentRepository: _FakeSourceDocumentRepository(),
          ocrTextRepository: _FakeOcrTextRepository(),
          aiGenerationRepository: _QuestionAiGenerationRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          aiGenerationOrchestrator: _ThrowingAiGenerationOrchestrator(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('下列方程中，是一元一次方程的是？'), 500);

    expect(find.text('下列方程中，是一元一次方程的是？'), findsOneWidget);
    expect(find.text('A. x² + 1 = 0'), findsOneWidget);
    expect(find.text('B. x + y = 3'), findsOneWidget);
    expect(find.text('C. 3x - 6 = 0'), findsOneWidget);
    expect(find.text('D. 1 / x = 2'), findsOneWidget);
    expect(find.text('答案：C'), findsOneWidget);
  });
  testWidgets('result refinement submits user feedback to orchestrator', (
    tester,
  ) async {
    final orchestrator = _RefiningAiGenerationOrchestrator();

    await tester.pumpWidget(
      MaterialApp(
        home: AiGenerationPage(
          documentId: 1,
          authRepository: _FakeAuthRepository(),
          sourceDocumentRepository: _FakeSourceDocumentRepository(),
          ocrTextRepository: _FakeOcrTextRepository(),
          aiGenerationRepository: _MindmapAiGenerationRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          aiGenerationOrchestrator: orchestrator,
        ),
      ),
    );

    await tester.pumpAndSettle();
    final refineButton = find.widgetWithText(OutlinedButton, '修改');
    await tester.scrollUntilVisible(refineButton, 500);
    await tester.ensureVisible(refineButton);
    await tester.pumpAndSettle();
    await tester.tap(refineButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '太简洁了，请展开每个分支');
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();

    expect(orchestrator.lastTaskType, AiTaskType.mindmapText);
    expect(orchestrator.lastCurrentResult, contains('一次函数'));
    expect(orchestrator.lastFeedback, '太简洁了，请展开每个分支');
  });
}

class _FakeAuthRepository extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    return const UserProfile(
      id: 1,
      username: 'tester',
      displayName: 'tester',
      bio: '',
      gender: '',
      avatarStyle: ProfilePresetIds.defaultAvatarStyle,
      backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
    );
  }
}

class _FakeSourceDocumentRepository extends SourceDocumentRepository {
  @override
  Future<SourceDocumentRecord?> getSourceDocumentById({
    required int userId,
    required int documentId,
  }) async {
    return SourceDocumentRecord(
      id: documentId,
      userId: userId,
      libraryId: 1,
      sourceType: SourceDocumentSourceType.galleryImport,
      imagePath: 'source_documents/page.png',
      title: 'OCR note',
      createdAt: DateTime(2026),
      ocrStatus: SourceDocumentOcrStatus.success,
      aiDone: false,
    );
  }
}

class _FakeOcrTextRepository extends OcrTextRepository {
  @override
  Future<OcrTextRecord?> getByDocumentId(int documentId) async {
    return OcrTextRecord(
      id: 1,
      documentId: documentId,
      rawText: 'raw text',
      cleanText: 'clean text',
      language: 'zh-CN',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }
}

class _FakeLlmConfigRepository extends LlmConfigRepository {
  @override
  Future<LlmProviderConfig?> getByUserId(int userId) async {
    return LlmProviderConfig(
      id: 1,
      userId: userId,
      provider: LlmProvider.minimax,
      apiMode: LlmApiMode.tokenPlan,
      apiKey: 'sk-cp-user-key',
      baseUrl: '',
      model: '',
      maxTokens: 4096,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }
}

class _EmptyAiGenerationRepository extends AiGenerationRepository {
  @override
  Future<List<AiGenerationTaskRecord>> fetchLatestTasksByDocument(
    int documentId,
  ) async {
    return const <AiGenerationTaskRecord>[];
  }

  @override
  Future<List<KnowledgeCardRecord>> fetchKnowledgeCards(int documentId) async {
    return const <KnowledgeCardRecord>[];
  }

  @override
  Future<ReviewOutlineRecord?> fetchReviewOutline(int documentId) async {
    return null;
  }

  @override
  Future<MindmapTextRecord?> fetchMindmapText(int documentId) async {
    return null;
  }

  @override
  Future<List<PracticeQuestionRecord>> fetchPracticeQuestions(
    int documentId,
  ) async {
    return const <PracticeQuestionRecord>[];
  }
}

class _QuestionAiGenerationRepository extends _EmptyAiGenerationRepository {
  @override
  Future<List<PracticeQuestionRecord>> fetchPracticeQuestions(
    int documentId,
  ) async {
    return [
      PracticeQuestionRecord(
        id: 1,
        documentId: documentId,
        questionText: '下列方程中，是一元一次方程的是？',
        answerText: 'C',
        analysisText: 'C 只有一个未知数，且未知数次数为 1。',
        difficulty: 'easy',
        reviewStatus: PracticeQuestionReviewStatus.pending,
        wrongCount: 0,
        createdAt: DateTime(2026),
        questionKind: PracticeQuestionKind.multipleChoice,
        optionsJson:
            '["A. x² + 1 = 0","B. x + y = 3","C. 3x - 6 = 0","D. 1 / x = 2"]',
      ),
    ];
  }
}

class _MindmapAiGenerationRepository extends _EmptyAiGenerationRepository {
  @override
  Future<MindmapTextRecord?> fetchMindmapText(int documentId) async {
    return MindmapTextRecord(
      id: 1,
      documentId: documentId,
      mindmapText: '一次函数\n- 定义',
      createdAt: DateTime(2026),
    );
  }
}

class _ThrowingAiGenerationOrchestrator extends AiGenerationOrchestrator {
  @override
  Future<AiSingleTaskResult> generateSingle({
    required int documentId,
    required String ocrText,
    required String taskType,
    LlmProviderConfig? llmConfig,
  }) async {
    throw StateError('network failed');
  }
}

class _RefiningAiGenerationOrchestrator extends AiGenerationOrchestrator {
  String? lastTaskType;
  String? lastCurrentResult;
  String? lastFeedback;

  @override
  Future<AiSingleTaskResult> regenerateWithFeedback({
    required int documentId,
    required String ocrText,
    required String taskType,
    required String currentResultText,
    required String feedback,
    LlmProviderConfig? llmConfig,
  }) async {
    lastTaskType = taskType;
    lastCurrentResult = currentResultText;
    lastFeedback = feedback;
    return AiSingleTaskResult(
      taskType: taskType,
      success: true,
      message: '修改成功',
    );
  }
}
