import 'package:flutter/material.dart';
import 'support/noop_learning_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/generator/ai_interview_service.dart';
import 'package:pxt1/generator/video_interview_capture_service.dart';
import 'package:pxt1/ui/pages/ai_interview_page.dart';

void main() {
  testWidgets('AI interview page supports video answer capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiInterviewPage(
          learningRepository: NoopLearningRepository(),
          authRepository: _FakeAuthRepository(),
          aiGenerationRepository: _FakeAiGenerationRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          interviewService: _FakeAiInterviewService(),
          videoCaptureService: _FakeVideoInterviewCaptureService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我准备好了'));
    await tester.pumpAndSettle();

    expect(find.text('AI 面试官'), findsOneWidget);
    expect(find.text('模拟摄像头预览'), findsOneWidget);

    await tester.tap(find.text('开始回答'));
    await tester.pumpAndSettle();
    expect(find.text('结束回答'), findsOneWidget);

    await tester.tap(find.text('结束回答'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A mapping with a domain.');
    await tester.ensureVisible(find.text('提交回答'));
    await tester.tap(find.text('提交回答'));
    await tester.pumpAndSettle();

    expect(find.text('得分 92/100'), findsOneWidget);
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
      score: 92,
      hitPoints: ['mapping'],
      missingPoints: ['domain boundary'],
      misconceptions: [],
      correction: 'Speak the domain condition more clearly.',
      standardAnswer: 'A function is a mapping from a domain to outputs.',
      nextFollowUp: 'Give one non-function example.',
    );
  }
}

class _FakeVideoInterviewCaptureService
    implements VideoInterviewCaptureService {
  @override
  Future<VideoInterviewCameraSession> createSession({
    bool enableAudio = true,
  }) async {
    return _FakeVideoInterviewCameraSession();
  }
}

class _FakeVideoInterviewCameraSession implements VideoInterviewCameraSession {
  var _isRecording = false;

  @override
  bool get isInitialized => true;

  @override
  bool get isRecording => _isRecording;

  @override
  Widget buildPreview() {
    return const Center(child: Text('模拟摄像头预览'));
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startRecording() async {
    _isRecording = true;
  }

  @override
  Future<CapturedVideoAnswer?> stopRecording() async {
    _isRecording = false;
    return const CapturedVideoAnswer(
      path: '/tmp/answer.mp4',
      name: 'answer.mp4',
    );
  }

  @override
  Future<void> dispose() async {}
}
