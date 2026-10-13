import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/agent/qsclaw_agent_service.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/generator/ai_interview_service.dart';
import 'package:pxt1/ui/pages/ai_interview_page.dart';
import 'package:pxt1/ui/pages/qsclaw_agent_page.dart';

void main() {
  testWidgets('QSClaw page uses Chinese product copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QsClawAgentPage(
          authRepository: _FakeAuthRepository(),
          agentService: _FakeQsClawAgentService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QSClaw'), findsWidgets);
    expect(find.byTooltip('\u5bf9\u8bdd\u83dc\u5355'), findsOneWidget);
    expect(find.byTooltip('\u5386\u53f2\u5bf9\u8bdd'), findsOneWidget);
  });

  testWidgets('AI interview page uses Chinese product copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiInterviewPage(
          authRepository: _FakeAuthRepository(),
          aiGenerationRepository: _FakeAiGenerationRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          interviewService: AiInterviewService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI \u9762\u8bd5\u5b98'), findsOneWidget);
    expect(find.text('\u6211\u51c6\u5907\u597d\u4e86'), findsOneWidget);
    expect(find.text('\u56de\u7b54\u8f6c\u5199'), findsOneWidget);
  });
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

class _FakeQsClawAgentService extends QsClawAgentService {}

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
    int? recordId,
  }) async {
    return [
      PracticeQuestionWithDocument(
        documentTitle: '\u9ad8\u7b49\u6570\u5b66\u7b14\u8bb0',
        question: PracticeQuestionRecord(
          id: 1,
          documentId: 2,
          questionText: '\u51fd\u6570\u662f\u4ec0\u4e48\uff1f',
          answerText:
              '\u51fd\u6570\u662f\u5b9a\u4e49\u57df\u5230\u503c\u57df\u7684\u5bf9\u5e94\u5173\u7cfb\u3002',
          analysisText:
              '\u9700\u8981\u8bf4\u660e\u5b9a\u4e49\u57df\u548c\u5bf9\u5e94\u5173\u7cfb\u3002',
          difficulty: 'easy',
          reviewStatus: PracticeQuestionReviewStatus.pending,
          wrongCount: 0,
          questionKind: PracticeQuestionKind.oral,
          createdAt: DateTime(2026, 6, 18),
        ),
      ),
    ];
  }
}
