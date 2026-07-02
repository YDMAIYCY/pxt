import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/generator/wrong_question_training_service.dart';
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

  testWidgets('wrong question training uses configured AI model', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final trainingService = _FakeWrongQuestionTrainingService();

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
          aiGenerationRepository: _FakeAiGenerationRepository(
            training: null,
            similarQuestions: const [],
          ),
          authRepository: _FakeAuthRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          trainingService: trainingService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成强化训练'));
    await tester.pumpAndSettle();

    expect(trainingService.receivedConfig?.apiKey, 'test-key');
    expect(trainingService.receivedConfig?.model, 'test-model');
    expect(find.text('强化训练已生成'), findsOneWidget);
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

class _FakeAuthRepository extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    return const UserProfile(
      id: 7,
      username: 'tester',
      displayName: 'tester',
      bio: '',
      gender: '',
      avatarStyle: ProfilePresetIds.defaultAvatarStyle,
      backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
    );
  }
}

class _FakeLlmConfigRepository extends LlmConfigRepository {
  @override
  Future<LlmProviderConfig?> getByUserId(int userId) async {
    return LlmProviderConfig.emptyForUser(userId).copyWith(
      apiKey: 'test-key',
      baseUrl: 'https://example.com/v1',
      model: 'test-model',
    );
  }
}

class _FakeWrongQuestionTrainingService extends WrongQuestionTrainingService {
  LlmProviderConfig? receivedConfig;

  @override
  Future<WrongQuestionTrainingDraft> generateForQuestion({
    required PracticeQuestionRecord question,
    LlmProviderConfig? llmConfig,
  }) async {
    receivedConfig = llmConfig;
    return const WrongQuestionTrainingDraft(
      causeTags: ['概念不清'],
      similarQuestions: [
        {
          'question_text': '相似题',
          'answer_text': '答案',
          'analysis_text': '解析',
          'difficulty': 'medium',
        },
      ],
    );
  }
}
