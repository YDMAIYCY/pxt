import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/knowledge_graph_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/models/knowledge_graph_records.dart';
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
              knowledgeGraphRepository: _EmptyKnowledgeGraphRepository(),
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

  testWidgets('knowledge graph keeps a pannable wide canvas on phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeTabPage(
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _EmptySourceDocumentRepository(),
            aiGenerationRepository: _EmptyAiGenerationRepository(),
            documentBatchRepository: _EmptyDocumentBatchRepository(),
            knowledgeGraphRepository: _GraphKnowledgeGraphRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('\u77e5\u8bc6\u56fe\u8c31'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('\u77e5\u8bc6\u56fe\u8c31'));
    await tester.pumpAndSettle();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.constrained, isFalse);
    expect(viewer.boundaryMargin.horizontal, greaterThanOrEqualTo(480));
    expect(find.byType(CustomPaint), findsWidgets);

    final linkHitTarget = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_GraphLinkHitTarget',
    );
    expect(linkHitTarget, findsWidgets);
    await tester.ensureVisible(linkHitTarget.first);
    await tester.pumpAndSettle();
    await tester.tap(linkHitTarget.first);
    await tester.pumpAndSettle();

    expect(find.textContaining('知识点1'), findsWidgets);
    expect(find.textContaining('知识点2'), findsWidgets);
  });
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
  Future<List<KnowledgeLibraryRecord>> fetchLibraries(
    int userId, {
    String source = 'all',
  }) async {
    return List<KnowledgeLibraryRecord>.of(_libraries);
  }

  @override
  Future<KnowledgeLibraryRecord> createLibrary({
    required int userId,
    required String name,
    String? description,
    String coverTheme = 'math',
    int coverColor = 0xFF5B90FF,
    String? operationKey,
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
    int? recordId,
  }) async {
    return const <PracticeQuestionWithDocument>[];
  }
}

class _EmptyKnowledgeGraphRepository extends KnowledgeGraphRepository {
  @override
  Future<List<KnowledgeConceptWithDocument>> fetchWeakConcepts({
    required int userId,
    int? libraryId,
    int limit = 20,
  }) async {
    return const <KnowledgeConceptWithDocument>[];
  }

  @override
  Future<List<KnowledgeConceptLinkRecord>> fetchLinksByLibrary({
    required int userId,
    int? libraryId,
    int limit = 100,
  }) async {
    return const <KnowledgeConceptLinkRecord>[];
  }
}

class _GraphKnowledgeGraphRepository extends _EmptyKnowledgeGraphRepository {
  @override
  Future<List<KnowledgeConceptWithDocument>> fetchWeakConcepts({
    required int userId,
    int? libraryId,
    int limit = 20,
  }) async {
    final now = DateTime(2026, 6, 30);
    return List.generate(12, (index) {
      return KnowledgeConceptWithDocument(
        concept: KnowledgeConceptRecord(
          id: index + 1,
          userId: userId,
          libraryId: libraryId,
          documentId: 100 + index,
          name: '知识点${index + 1}',
          masteryScore: (index * 9).clamp(0, 100),
          weaknessScore: (100 - index * 7).clamp(0, 100),
          createdAt: now,
          updatedAt: now,
        ),
        documentTitle: '资料${index + 1}',
      );
    });
  }

  @override
  Future<List<KnowledgeConceptLinkRecord>> fetchLinksByLibrary({
    required int userId,
    int? libraryId,
    int limit = 100,
  }) async {
    final now = DateTime(2026, 6, 30);
    return List.generate(11, (index) {
      return KnowledgeConceptLinkRecord(
        id: index + 1,
        userId: userId,
        libraryId: libraryId,
        fromConceptId: index + 1,
        toConceptId: index + 2,
        relationLabel: '前置依赖',
        createdAt: now,
      );
    });
  }
}
