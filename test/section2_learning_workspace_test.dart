import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/learning_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/generator/learning_resource_service.dart';
import 'package:pxt1/ui/pages/learning_workspace_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'picture understanding asks for topic and direction before saving core resources',
    (tester) async {
      final app = (await tester.runAsync(
        () => AppDatabase.openForTesting(databaseFactoryFfi),
      ))!;
      final db = await app.database;
      final learning = LearningRepository(database: app);
      late SourceDocumentRecord document;
      late int library;
      await tester.runAsync(() async {
        await db.insert('users', {
          'id': 1,
          'username': 'learner',
          'password_hash': 'x',
          'password_salt': 'x',
          'created_at': '2026-10-13',
          'updated_at': '2026-10-13',
        });
        library = (await KnowledgeLibraryRepository(
          database: app,
        ).ensureDefaultLibrary(1)).id;
        document = await SourceDocumentRepository(database: app)
            .createSourceDocument(
              userId: 1,
              libraryId: library,
              sourceType: 'gallery_import',
              imagePath: 'fixture.png',
              title: '来源照片',
            );
        await LlmConfigRepository(database: app).save(
          LlmProviderConfig.emptyForUser(1).copyWith(
            provider: 'custom',
            apiKey: 'fixture',
            model: 'vision',
            baseUrl: 'https://example.com',
          ),
        );
      });
      final service = _FixtureImageService(app, library);
      await tester.pumpWidget(
        MaterialApp(
          home: LearningWorkspacePage(
            documentId: document.id,
            database: app,
            authRepository: _FixtureAuth(),
            resourceService: service,
          ),
        ),
      );
      await _waitFor(tester, '理解图片');
      await tester.tap(find.text('理解图片'));
      await _waitFor(tester, '选择想学习的主题');
      expect(
        await tester.runAsync(() => learning.resources(1, document.id)),
        isEmpty,
      );
      await tester.tap(find.text('Attention 机制'));
      await _waitFor(tester, '你想了解什么？');
      await tester.tap(find.text('学习原理'));
      await _waitFor(tester, '关联知识库（可多选）');
      await tester.tap(find.text('保存归类'));
      await _waitFor(tester, 'Attention 机制');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final saved = await tester.runAsync(
        () => learning.resources(1, document.id),
      );
      expect(saved, hasLength(1));
      expect(saved!.single.type, 'knowledge_cards');
      expect(
        await tester.runAsync(() => service.understanding(document.id)),
        containsPair('direction', '学习原理'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => db.close());
    },
  );
}

Future<void> _waitFor(WidgetTester tester, String label) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text(label).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  expect(find.text(label), findsWidgets);
}

class _FixtureAuth extends AuthRepository {
  @override
  Future<UserProfile?> getCurrentUserProfile() async => const UserProfile(
    id: 1,
    username: 'learner',
    displayName: 'learner',
    bio: '',
    gender: '',
    avatarStyle: ProfilePresetIds.defaultAvatarStyle,
    backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
  );
}

class _FixtureImageService extends LearningResourceService {
  _FixtureImageService(AppDatabase db, this.library) : super(database: db);
  final int library;
  @override
  Future<Map<String, dynamic>> focusTopic(
    SourceDocumentRecord document,
    LlmProviderConfig config,
    Map<String, dynamic> analysis,
    Map topic,
    String direction, {
    String? imagePath,
  }) async => Map<String, dynamic>.from(topic);
  @override
  Future<Map<String, dynamic>> analyzeImage(
    SourceDocumentRecord document,
    LlmProviderConfig config, {
    String? imagePath,
  }) async => {
    'content_type': '结构图',
    'directions': ['学习原理', '学习应用'],
    'uncertainties': ['一处标注不清晰'],
    'topics': [
      {
        'title': 'Attention 机制',
        'summary': '加权聚合',
        'concepts': [
          {'name': 'Attention', 'summary': '加权聚合', 'evidence_text': '结构图'},
        ],
        'cards': [
          {'title': 'Attention', 'content': '权重归一化后聚合'},
        ],
      },
      {'title': '矩阵运算', 'summary': '线性变换'},
    ],
  };
  @override
  Future<List<int>> recommendLibraries(
    SourceDocumentRecord document,
    LlmProviderConfig config,
  ) async => [library];
}
