import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/generator/ai_interview_service.dart';
import 'package:pxt1/ui/pages/ai_interview_page.dart';

void main() {
  testWidgets('AI interview page scores an answer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiInterviewPage(
          authRepository: _FakeAuthRepository(),
          aiGenerationRepository: _FakeAiGenerationRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          interviewService: _FakeAiInterviewService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('What is a function?'), findsOneWidget);

    await tester.tap(find.text('我准备好了'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A mapping with a domain.');
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交回答'));
    await tester.pumpAndSettle();

    expect(find.text('得分 90/100'), findsOneWidget);
    expect(find.textContaining('mapping'), findsWidgets);
    expect(find.textContaining('domain'), findsWidgets);

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入追问'));
    await tester.pumpAndSettle();

    expect(find.text('Why does the domain matter?'), findsOneWidget);
  });
}

class _FakeAuthRepository extends AuthRepository {
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
      baseUrl: 'https://example.com',
      model: 'test-model',
    );
  }
}

class _FakeAiGenerationRepository extends AiGenerationRepository {
  @override
  Future<List<PracticeQuestionWithDocument>> fetchPracticeQuestionsByUser({
    required int userId,
    String? reviewStatus,
    int? libraryId,
    int limit = 100,
  }) async {
    return [
      PracticeQuestionWithDocument(
        documentTitle: 'Calculus notes',
        question: PracticeQuestionRecord(
          id: 1,
          documentId: 2,
          questionText: 'What is a function?',
          answerText: 'A function maps each input in a domain to one output.',
          analysisText: 'Mention domain and mapping.',
          difficulty: 'easy',
          reviewStatus: PracticeQuestionReviewStatus.pending,
          wrongCount: 0,
          questionKind: PracticeQuestionKind.oral,
          expectedKeywordsJson: '["domain","mapping"]',
          createdAt: DateTime(2026, 6, 17),
        ),
      ),
    ];
  }
}

class _FakeAiInterviewService extends AiInterviewService {
  @override
  Future<AiInterviewFeedback> evaluateAnswer({
    required PracticeQuestionWithDocument question,
    required String userAnswer,
    required LlmProviderConfig config,
  }) async {
    return const AiInterviewFeedback(
      score: 90,
      hitPoints: ['mapping'],
      missingPoints: ['domain boundary'],
      misconceptions: [],
      correction: 'Add the domain explicitly.',
      standardAnswer: 'A function is a mapping from a domain to outputs.',
      nextFollowUp: 'Why does the domain matter?',
    );
  }
}
