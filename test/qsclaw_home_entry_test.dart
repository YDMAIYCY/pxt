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

  testWidgets('HomeTabPage does not show AI interview entry', (tester) async {
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

    expect(find.text('AI 面试'), findsNothing);
    expect(find.text('AI 面试官'), findsNothing);
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
      '\u62cd\u7167\u8bc6\u522b',
      '\u5bfc\u5165\u8d44\u6599',
      '\u6700\u8fd1\u5b66\u4e60\u5305',
      '\u6700\u8fd1\u5904\u7406\u8d44\u6599',
      '\u6700\u8fd1\u751f\u6210\u6210\u679c',
      '\u5b66\u4e60\u7edf\u8ba1',
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
