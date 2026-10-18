import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/knowledge_graph_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/models/knowledge_graph_records.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/ui/pages/tabs/home_tab_page.dart';
import 'package:pxt1/ui/pages/tabs/knowledge_tab_page.dart';
import 'package:pxt1/ui/pages/tabs/profile_tab_page.dart';
import 'package:pxt1/ui/pages/tabs/tasks_tab_page.dart';

void main() {
  group('cross tab refresh integration', () {
    testWidgets('HomeTabPage reloads when refreshVersion changes', (
      tester,
    ) async {
      final sourceDocuments = _FakeSourceDocumentRepository();

      await tester.pumpWidget(
        _wrap(
          HomeTabPage(
            refreshVersion: 0,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: sourceDocuments,
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sourceDocuments.recentCalls, 1);

      await tester.pumpWidget(
        _wrap(
          HomeTabPage(
            refreshVersion: 1,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: sourceDocuments,
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sourceDocuments.recentCalls, 2);
    });

    testWidgets('KnowledgeTabPage reloads when refreshVersion changes', (
      tester,
    ) async {
      final libraries = _FakeKnowledgeLibraryRepository();
      final graph = _FakeKnowledgeGraphRepository();

      await tester.pumpWidget(
        _wrap(
          KnowledgeTabPage(
            refreshVersion: 0,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeGraphRepository: graph,
            knowledgeLibraryRepository: libraries,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(libraries.fetchCalls, 1);

      await tester.pumpWidget(
        _wrap(
          KnowledgeTabPage(
            refreshVersion: 1,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeGraphRepository: graph,
            knowledgeLibraryRepository: libraries,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(libraries.fetchCalls, 2);
    });

    testWidgets('TasksTabPage reloads when refreshVersion changes', (
      tester,
    ) async {
      final sourceDocuments = _FakeSourceDocumentRepository();

      await tester.pumpWidget(
        _wrap(
          TasksTabPage(
            refreshVersion: 0,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: sourceDocuments,
            aiGenerationRepository: _FakeAiGenerationRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sourceDocuments.allCalls, 1);

      await tester.pumpWidget(
        _wrap(
          TasksTabPage(
            refreshVersion: 1,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: sourceDocuments,
            aiGenerationRepository: _FakeAiGenerationRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sourceDocuments.allCalls, 2);
    });

    testWidgets('ProfileTabPage reloads when refreshVersion changes', (
      tester,
    ) async {
      final aiGeneration = _FakeAiGenerationRepository();

      await tester.pumpWidget(
        _wrap(
          ProfileTabPage(
            refreshVersion: 0,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            llmConfigRepository: _FakeLlmConfigRepository(),
            aiGenerationRepository: aiGeneration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(aiGeneration.studyStatsCalls, 1);

      await tester.pumpWidget(
        _wrap(
          ProfileTabPage(
            refreshVersion: 1,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            llmConfigRepository: _FakeLlmConfigRepository(),
            aiGenerationRepository: aiGeneration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(aiGeneration.studyStatsCalls, 2);
    });
  });

  testWidgets('Home current quick entries render without legacy AI entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HomeTabPage(
          refreshVersion: 0,
          authRepository: _FakeAuthRepository(),
          sourceDocumentRepository: _FakeSourceDocumentRepository(),
          aiGenerationRepository: _FakeAiGenerationRepository(),
          documentBatchRepository: _FakeDocumentBatchRepository(),
          knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('拍一下，开始学习'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('今日学习建议'), 100);
    await tester.pumpAndSettle();
    expect(find.text('今日学习建议'), findsOneWidget);
    expect(find.text('益智游戏'), findsNothing);
    expect(
      find.textContaining('\u690d\u5165\u6f14\u793a\u6570\u636e'),
      findsNothing,
    );
  });

  testWidgets('home companion entry uses the new fourth tab', (tester) async {
    final opened = <int>[];
    await tester.pumpWidget(
      _wrap(
        HomeTabPage(
          authRepository: _FakeAuthRepository(),
          sourceDocumentRepository: _FakeSourceDocumentRepository(),
          aiGenerationRepository: _FakeAiGenerationRepository(),
          documentBatchRepository: _FakeDocumentBatchRepository(),
          knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          onOpenTab: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('AI 学伴'), 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 学伴'));
    expect(opened, [3]);
  });

  testWidgets('Profile keeps favorites entry without wrong-question shortcut', (
    tester,
  ) async {
    final openedTabs = <int>[];

    await tester.pumpWidget(
      _wrap(
        ProfileTabPage(
          refreshVersion: 0,
          authRepository: _FakeAuthRepository(),
          sourceDocumentRepository: _FakeSourceDocumentRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          aiGenerationRepository: _FakeAiGenerationRepository(),
          onOpenTab: openedTabs.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的错题收藏'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('收藏'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(openedTabs, isEmpty);
    expect(find.text('我的收藏'), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

const _testUser = UserProfile(
  id: 1,
  username: 'tester',
  displayName: 'tester',
  bio: '',
  gender: '',
  avatarStyle: ProfilePresetIds.defaultAvatarStyle,
  backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
);

class _FakeAuthRepository extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<UserProfile?> getCurrentUserProfile() async => _testUser;
}

class _FakeSourceDocumentRepository extends SourceDocumentRepository {
  int recentCalls = 0;
  int allCalls = 0;

  @override
  Future<List<SourceDocumentRecord>> fetchRecentSourceDocuments({
    required int userId,
    int? libraryId,
    bool includeBatchPages = true,
    int limit = 5,
  }) async {
    recentCalls++;
    return const [];
  }

  @override
  Future<List<SourceDocumentRecord>> fetchAllSourceDocuments({
    required int userId,
    int? libraryId,
    int limit = 100,
  }) async {
    allCalls++;
    return const [];
  }
}

class _FakeDocumentBatchRepository extends DocumentBatchRepository {
  @override
  Future<List<DocumentBatchRecord>> fetchRecentBatches({
    required int userId,
    int? libraryId,
    int limit = 20,
  }) async {
    return const [];
  }
}

class _FakeKnowledgeLibraryRepository extends KnowledgeLibraryRepository {
  int fetchCalls = 0;

  @override
  Future<List<KnowledgeLibraryRecord>> fetchLibraries(int userId) async {
    fetchCalls++;
    return [
      KnowledgeLibraryRecord(
        id: 1,
        userId: userId,
        name: 'Default',
        createdAt: DateTime(2026, 5, 29),
        updatedAt: DateTime(2026, 5, 29),
      ),
    ];
  }
}

class _FakeKnowledgeGraphRepository extends KnowledgeGraphRepository {
  int fetchCalls = 0;

  @override
  Future<List<KnowledgeConceptWithDocument>> fetchWeakConcepts({
    required int userId,
    int? libraryId,
    int limit = 20,
  }) async {
    fetchCalls++;
    return const [];
  }

  @override
  Future<List<KnowledgeConceptLinkRecord>> fetchLinksByLibrary({
    required int userId,
    int? libraryId,
    int limit = 100,
  }) async {
    return const [];
  }
}

class _FakeAiGenerationRepository extends AiGenerationRepository {
  int studyStatsCalls = 0;

  @override
  Future<List<GeneratedContentRecord>> fetchRecentGeneratedContents({
    required int userId,
    int? libraryId,
    int limit = 12,
  }) async {
    return const [];
  }

  @override
  Future<StudyOverviewStats> fetchStudyOverviewStats(int userId) async {
    studyStatsCalls++;
    return const StudyOverviewStats(
      documentCount: 0,
      ocrSuccessCount: 0,
      generatedResultCount: 0,
      practiceQuestionCount: 0,
      pendingPracticeCount: 0,
      wrongQuestionCount: 0,
      masteredQuestionCount: 0,
    );
  }

  @override
  Future<List<AiTaskWithDocument>> fetchAiTasksByUser({
    required int userId,
    int? libraryId,
    int limit = 40,
  }) async {
    return const [];
  }

  @override
  Future<List<PracticeQuestionWithDocument>> fetchTodayPracticeQuestionsByUser({
    required int userId,
    int? libraryId,
    DateTime? now,
    int limit = 100,
  }) async {
    return const [];
  }

  @override
  Future<List<PracticeQuestionWithDocument>>
  fetchOverduePracticeQuestionsByUser({
    required int userId,
    int? libraryId,
    DateTime? now,
    int limit = 100,
  }) async {
    return const [];
  }

  @override
  Future<List<PracticeQuestionWithDocument>> fetchPracticeQuestionsByUser({
    required int userId,
    String? reviewStatus,
    int? libraryId,
    int limit = 100,
  }) async {
    return const [];
  }
}

class _FakeLlmConfigRepository extends LlmConfigRepository {
  @override
  Future<LlmProviderConfig?> getByUserId(int userId) async => null;
}
