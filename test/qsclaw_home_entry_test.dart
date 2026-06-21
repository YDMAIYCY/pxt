import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/debug/debug_demo_data_seeder.dart';
import 'package:pxt1/ui/pages/tabs/home_tab_page.dart';

void main() {
  testWidgets('HomeTabPage opens QSClaw agent entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabPage(
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
            qsClawPageBuilder: () => const _MarkerPage('qsclaw-opened'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('QSClaw'), 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text('QSClaw'));
    await tester.pumpAndSettle();

    expect(find.text('qsclaw-opened'), findsOneWidget);
  });

  testWidgets('HomeTabPage opens AI interview entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabPage(
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
            aiInterviewPageBuilder: () =>
                const _MarkerPage('ai-interview-opened'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const aiInterviewLabel = 'AI \u9762\u8bd5\u5b98';
    await tester.scrollUntilVisible(find.text(aiInterviewLabel), 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text(aiInterviewLabel));
    await tester.pumpAndSettle();

    expect(find.text('ai-interview-opened'), findsOneWidget);
  });

  testWidgets('HomeTabPage shows debug demo data entry in debug builds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabPage(
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\u690d\u5165\u6f14\u793a\u6570\u636e'), findsOneWidget);
  });

  testWidgets('HomeTabPage seeds debug demo data with visible feedback', (
    tester,
  ) async {
    final seeder = _FakeDebugDemoDataSeeder();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabPage(
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
            debugDemoDataSeeder: seeder,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('\u690d\u5165\u6f14\u793a\u6570\u636e'),
      120,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('\u690d\u5165\u6f14\u793a\u6570\u636e'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(seeder.seededUserId, 7);
    expect(
      find.text(
        '\u6f14\u793a\u6570\u636e\u5df2\u690d\u5165\u5f53\u524d'
        '\u8c03\u8bd5\u8d26\u53f7',
      ),
      findsWidgets,
    );
  });

  testWidgets('HomeTabPage renders core Chinese labels without mojibake', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabPage(
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            aiGenerationRepository: _FakeAiGenerationRepository(),
            documentBatchRepository: _FakeDocumentBatchRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const labels = [
      '\u5feb\u901f\u5165\u53e3',
      '\u62cd\u7167\u8d44\u6599',
      '\u5bfc\u5165\u56fe\u7247',
      '\u591a\u56fe\u5bfc\u5165',
      '\u5bfc\u5165 PDF',
      '\u751f\u6210 AI \u7ed3\u679c',
      '\u5237\u590d\u4e60\u9898',
      '\u76ca\u667a\u6e38\u620f',
      '\u6700\u8fd1\u5b66\u4e60\u5305',
      '\u6700\u8fd1\u5904\u7406\u8d44\u6599',
      '\u6700\u8fd1\u751f\u6210\u6210\u679c',
      '\u5b66\u4e60\u7edf\u8ba1',
      '\u690d\u5165\u6f14\u793a\u6570\u636e',
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }

    expect(find.textContaining('\u9396'), findsNothing);
    expect(find.textContaining('\u9422'), findsNothing);
  });
}

class _MarkerPage extends StatelessWidget {
  const _MarkerPage(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
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

class _FakeSourceDocumentRepository extends SourceDocumentRepository {
  @override
  Future<List<SourceDocumentRecord>> fetchRecentSourceDocuments({
    required int userId,
    int? libraryId,
    bool includeBatchPages = true,
    int limit = 5,
  }) async {
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
  @override
  Future<List<KnowledgeLibraryRecord>> fetchLibraries(int userId) async {
    return const [];
  }
}

class _FakeAiGenerationRepository extends AiGenerationRepository {
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
}

class _FakeDebugDemoDataSeeder extends DebugDemoDataSeeder {
  int? seededUserId;

  @override
  Future<void> seedForUser(int userId) async {
    seededUserId = userId;
  }
}
