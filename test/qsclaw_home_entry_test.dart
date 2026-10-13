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
  Widget home({ValueChanged<int>? onOpenTab}) => MaterialApp(
    home: Scaffold(
      body: HomeTabPage(
        authRepository: _FakeAuthRepository(),
        sourceDocumentRepository: _FakeSourceDocumentRepository(),
        aiGenerationRepository: _FakeAiGenerationRepository(),
        documentBatchRepository: _FakeDocumentBatchRepository(),
        knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
        onOpenTab: onOpenTab,
      ),
    ),
  );

  testWidgets(
    'home prioritizes capture and learning suggestions without games',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      for (final label in [
        '拍学通',
        '今天想学习什么？',
        '拍一下，开始学习',
        '拍照',
        '相册',
        '文件',
        '继续学习',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.scrollUntilVisible(find.text('AI 快速面试'), 100);
      expect(find.text('今日学习建议'), findsOneWidget);
      expect(find.text('益智游戏'), findsNothing);
      expect(find.text('QSClaw'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home links to practice and companion navigation indices', (
    tester,
  ) async {
    final opened = <int>[];
    await tester.pumpWidget(home(onOpenTab: opened.add));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('查看全部'), 120);
    await tester.tap(find.text('查看全部'));
    expect(opened, [2]);
    await tester.scrollUntilVisible(find.text('AI 学伴'), 120);
    await tester.tap(find.text('AI 学伴'));
    expect(opened, [2, 3]);
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
