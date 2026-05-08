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
import 'package:pxt1/ui/pages/tabs/knowledge_tab_page.dart';

void main() {
  testWidgets(
    'creating a knowledge library selects it without Flutter errors',
    (tester) async {
      final libraries = _FakeKnowledgeLibraryRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnowledgeTabPage(
              authRepository: _FakeAuthRepository(),
              sourceDocumentRepository: _EmptySourceDocumentRepository(),
              aiGenerationRepository: _EmptyAiGenerationRepository(),
              documentBatchRepository: _EmptyDocumentBatchRepository(),
              knowledgeLibraryRepository: libraries,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('新建知识库'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '英语');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(find.textContaining('英语'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}

// ========== 测试假对象 ==========
// 隔离真实数据库，只验证知识库创建弹窗和页面刷新行为。

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

class _FakeKnowledgeLibraryRepository extends KnowledgeLibraryRepository {
  final List<KnowledgeLibraryRecord> _libraries = [
    KnowledgeLibraryRecord(
      id: 1,
      userId: 1,
      name: '默认知识库',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  @override
  Future<List<KnowledgeLibraryRecord>> fetchLibraries(int userId) async {
    return List<KnowledgeLibraryRecord>.of(_libraries);
  }

  @override
  Future<KnowledgeLibraryRecord> createLibrary({
    required int userId,
    required String name,
    String? description,
  }) async {
    final library = KnowledgeLibraryRecord(
      id: _libraries.length + 1,
      userId: userId,
      name: name.trim(),
      description: description,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    _libraries.add(library);
    return library;
  }
}

class _EmptySourceDocumentRepository extends SourceDocumentRepository {
  @override
  Future<List<SourceDocumentRecord>> fetchAllSourceDocuments({
    required int userId,
    int? libraryId,
    int limit = 100,
  }) async {
    return const <SourceDocumentRecord>[];
  }
}

class _EmptyDocumentBatchRepository extends DocumentBatchRepository {
  @override
  Future<List<DocumentBatchRecord>> fetchRecentBatches({
    required int userId,
    int? libraryId,
    int limit = 20,
  }) async {
    return const <DocumentBatchRecord>[];
  }
}

class _EmptyAiGenerationRepository extends AiGenerationRepository {
  @override
  Future<List<GeneratedContentRecord>> fetchRecentGeneratedContents({
    required int userId,
    int? libraryId,
    int limit = 12,
  }) async {
    return const <GeneratedContentRecord>[];
  }

  @override
  Future<List<PracticeQuestionWithDocument>> fetchPracticeQuestionsByUser({
    required int userId,
    String? reviewStatus,
    int? libraryId,
    int limit = 100,
  }) async {
    return const <PracticeQuestionWithDocument>[];
  }
}
