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

    await tester.ensureVisible(find.text('QSClaw'));
    await tester.tap(find.text('QSClaw'));
    await tester.pumpAndSettle();

    expect(find.text('qsclaw-opened'), findsOneWidget);
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
