import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/ai_chat_repository.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_context_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/ai_chat_records.dart';
import 'package:pxt1/database/models/knowledge_context_source.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/generator/ai_chat_service.dart';
import 'package:pxt1/ui/pages/ai_chat_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    // EClaw resolves its knowledge scope, session ownership and agent tasks
    // through real repositories, so the signed-in user has to exist.
    await db.insert('users', {
      'id': _testUser.id,
      'username': 'tester',
      'password_hash': 'x',
      'password_salt': 'x',
      'created_at': '2026-05-29T08:00:00.000Z',
      'updated_at': '2026-05-29T08:00:00.000Z',
    });
  });

  tearDown(() async => db.close());

  testWidgets('EClaw creates, renames, switches, and deletes chats', (
    tester,
  ) async {
    final chats = AiChatRepository(database: app);
    // testWidgets runs the body in a fake-async zone, so real SQLite I/O only
    // progresses inside runAsync.
    final seededId = await tester.runAsync(() async {
      final seeded = await chats.createSession(
        userId: _testUser.id,
        title: '函数复习',
      );
      await chats.appendMessage(
        sessionId: seeded.id,
        role: AiChatMessageRole.assistant,
        content: '先看定义',
      );
      return seeded.id;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          database: app,
          authRepository: _FakeAuthRepository(app),
          llmConfigRepository: _FakeLlmConfigRepository(_testConfig, app),
          aiChatRepository: chats,
          knowledgeContextRepository: _FakeKnowledgeContextRepository(app),
          aiChatService: _FakeAiChatService(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('EClaw'), findsOneWidget);
    expect(find.textContaining('先看定义'), findsOneWidget);

    await tester.tap(find.byTooltip('对话菜单'));
    await _settle(tester);
    await tester.tap(find.text('新建对话'));
    await _settle(tester);
    expect(find.text('EClaw'), findsWidgets);

    await tester.enterText(find.byType(TextField), '导数是什么');
    await tester.tap(find.byTooltip('发送'));
    await _settle(tester);
    expect(find.textContaining('这是 AI 回复'), findsOneWidget);

    await tester.tap(find.byTooltip('对话菜单'));
    await _settle(tester);
    await tester.tap(find.text('重命名对话'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, '导数冲刺');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _settle(tester);
    final titlesAfterRename = await tester.runAsync(
      () async => (await db.query('ai_chat_sessions')).map(
        (row) => row['title'],
      ),
    );
    expect(titlesAfterRename, contains('导数冲刺'));

    await tester.tap(find.byTooltip('历史对话'));
    await _settle(tester);
    await tester.tap(find.text('函数复习').last);
    await _settle(tester);
    expect(find.textContaining('先看定义'), findsOneWidget);

    await tester.tap(find.byTooltip('对话菜单'));
    await _settle(tester);
    await tester.tap(find.text('删除对话'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _settle(tester);

    final remaining = await tester.runAsync(() => db.query('ai_chat_sessions'));
    expect(
      remaining!.map((row) => row['id']),
      isNot(contains(seededId)),
      reason: '删除的是当前打开的会话',
    );
    expect(
      remaining.map((row) => row['title']),
      contains('导数冲刺'),
    );
  });

  testWidgets('EClaw gates a debug write behind explicit confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          database: app,
          authRepository: _FakeAuthRepository(app),
          // An unconfigured provider keeps task planning local and
          // deterministic instead of calling the model.
          llmConfigRepository: _FakeLlmConfigRepository(null, app),
          aiChatRepository: AiChatRepository(database: app),
          knowledgeContextRepository: _FakeKnowledgeContextRepository(app),
          aiChatService: _FakeAiChatService(),
        ),
      ),
    );
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '植入演示数据');
    await tester.tap(find.byTooltip('发送'));
    await _settle(tester);

    // Seeding demo data writes to the database, so the executor has to stop and
    // ask before running the tool.
    expect(find.textContaining('请确认操作'), findsOneWidget);
  });
}

/// Real SQLite FFI work runs outside fake widget time, so `pumpAndSettle` can
/// never observe the page settling. Pump with real async gaps instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _testUser = UserProfile(
  id: 7,
  username: 'tester',
  displayName: 'tester',
  bio: '',
  gender: '',
  avatarStyle: ProfilePresetIds.defaultAvatarStyle,
  backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
);

final _testConfig = LlmProviderConfig(
  id: 1,
  userId: _testUser.id,
  provider: LlmProvider.minimax,
  apiMode: LlmApiMode.tokenPlan,
  apiKey: 'sk-cp-test-key',
  baseUrl: '',
  model: 'MiniMax-M2.7',
  maxTokens: 4096,
  createdAt: DateTime.utc(2026, 5, 29),
  updatedAt: DateTime.utc(2026, 5, 29),
);

// The fakes still inherit real ownership/scope checks, so they are given the
// test database rather than falling through to the uninitialised global one.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(AppDatabase database) : super(database: database);

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<UserProfile?> getCurrentUserProfile() async => _testUser;
}

class _FakeLlmConfigRepository extends LlmConfigRepository {
  _FakeLlmConfigRepository(this.config, AppDatabase database)
    : super(database: database);

  final LlmProviderConfig? config;
  @override
  Future<LlmProviderConfig?> getByUserId(int userId) async => config;
}

class _FakeAiChatService extends AiChatService {
  @override
  Future<String> generateReply({
    required LlmProviderConfig config,
    required List<AiChatMessageRecord> messages,
    List<KnowledgeContextSource> contextSources = const [],
  }) async {
    return '这是 AI 回复';
  }
}

class _FakeKnowledgeContextRepository extends KnowledgeContextRepository {
  _FakeKnowledgeContextRepository(AppDatabase database)
    : super(database: database);

  @override
  Future<List<KnowledgeContextSource>> search({
    required int userId,
    required String query,
    int? libraryId,
    int? knowledgeBaseId,
    int? importRecordId,
    int? documentId,
    int limit = 6,
  }) async {
    return const <KnowledgeContextSource>[];
  }
}
