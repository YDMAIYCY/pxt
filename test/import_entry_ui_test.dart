import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/camera/document_input_contract.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/knowledge_graph_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/pipeline/document_ingest_service.dart';
import 'package:pxt1/ui/pages/guide_page.dart';
import 'package:pxt1/ui/pages/tabs/home_tab_page.dart';

void main() {
  for (final entry in {
    '相册导入': BatchDocumentInputSource.multiImage,
    '文档导入': BatchDocumentInputSource.document,
  }.entries) {
    testWidgets(
      '${entry.key} uses the correct picker after library selection',
      (tester) async {
        final ingest = _Ingest();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeTabPage(
                authRepository: _Auth(),
                sourceDocumentRepository: _Documents(),
                documentBatchRepository: _Batches(),
                aiGenerationRepository: _Ai(),
                knowledgeGraphRepository: _Graph(),
                knowledgeLibraryRepository: _Libraries(),
                documentIngestService: ingest,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('导入资料'), 120);
        await tester.pumpAndSettle();
        await tester.tap(find.text('导入资料'));
        await tester.pumpAndSettle();
        expect(find.text('相册导入'), findsOneWidget);
        expect(find.text('文档导入'), findsOneWidget);
        expect(find.text('多图导入'), findsNothing);
        expect(find.text('导入 PDF'), findsNothing);
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        await tester.tap(find.text('测试知识库'));
        await tester.pumpAndSettle();
        expect(ingest.source, entry.value);
        expect(ingest.libraryId, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('guide renders the supplied artwork at phone size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: GuidePage(),
        ),
      ),
    );
    final asset = tester.widget<Image>(find.byType(Image)).image as AssetImage;
    expect(asset.assetName, 'assets/images/1.png');
    await tester.runAsync(() async {
      final context = tester.element(find.byType(GuidePage));
      await precacheImage(asset, context);
    });
    await tester.pumpAndSettle();
    expect(find.text('进入登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/import_validation').create(recursive: true);
      await File(
        'build/import_validation/guide_preview.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}

class _Ingest extends DocumentIngestService {
  BatchDocumentInputSource? source;
  int? libraryId;
  @override
  Future<DocumentBatchRecord?> importBatchFromInput({
    required int userId,
    int? libraryId,
    required BatchDocumentInputSource source,
  }) async {
    this.source = source;
    this.libraryId = libraryId;
    return null;
  }
}

class _Auth extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<UserProfile?> getCurrentUserProfile() async => const UserProfile(
    id: 7,
    username: 'test',
    displayName: 'test',
    bio: '',
    gender: '',
    avatarStyle: ProfilePresetIds.defaultAvatarStyle,
    backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
  );
}

class _Documents extends SourceDocumentRepository {
  @override
  Future<List<SourceDocumentRecord>> fetchRecentSourceDocuments({
    required int userId,
    int? libraryId,
    bool includeBatchPages = true,
    int limit = 5,
  }) async => [];
}

class _Batches extends DocumentBatchRepository {
  @override
  Future<List<DocumentBatchRecord>> fetchRecentBatches({
    required int userId,
    int? libraryId,
    int limit = 20,
  }) async => [];
}

class _Libraries extends KnowledgeLibraryRepository {
  @override
  Future<List<KnowledgeLibraryRecord>> fetchLibraries(
    int userId, {
    String source = 'all',
  }) async => [
    KnowledgeLibraryRecord(
      id: 3,
      userId: userId,
      name: '测试知识库',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];
}

class _Graph extends KnowledgeGraphRepository {
  @override
  Future<List<KnowledgeNextBestAction>> fetchNextBestActions({
    required int userId,
    int? libraryId,
    int limit = 3,
  }) async => [];
}

class _Ai extends AiGenerationRepository {
  @override
  Future<List<GeneratedContentRecord>> fetchRecentGeneratedContents({
    required int userId,
    int? libraryId,
    int limit = 12,
  }) async => [];
  @override
  Future<StudyOverviewStats> fetchStudyOverviewStats(int userId) async =>
      const StudyOverviewStats(
        documentCount: 0,
        ocrSuccessCount: 0,
        generatedResultCount: 0,
        practiceQuestionCount: 0,
        pendingPracticeCount: 0,
        wrongQuestionCount: 0,
        masteredQuestionCount: 0,
      );
}
