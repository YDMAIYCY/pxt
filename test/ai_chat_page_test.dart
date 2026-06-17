import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_chat_repository.dart';
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
  testWidgets('AI chat page creates, renames, switches, and deletes chats', (
    tester,
  ) async {
    final repository = _FakeAiChatRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          authRepository: _FakeAuthRepository(),
          llmConfigRepository: _FakeLlmConfigRepository(),
          aiChatRepository: repository,
          knowledgeContextRepository: _FakeKnowledgeContextRepository(),
          aiChatService: _FakeAiChatService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('函数复习'), findsOneWidget);
    expect(find.text('先看定义'), findsOneWidget);

    await tester.tap(find.byTooltip('聊天菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建聊天'));
    await tester.pumpAndSettle();
    expect(find.text('开始新的 AI Chat'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '帮我复习导数');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(find.textContaining('这是 AI 回复'), findsOneWidget);

    await tester.tap(find.byTooltip('聊天菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名聊天'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '导数冲刺');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('导数冲刺'), findsOneWidget);

    await tester.tap(find.byTooltip('历史聊天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('函数复习').last);
    await tester.pumpAndSettle();
    expect(find.text('先看定义'), findsOneWidget);

    await tester.tap(find.byTooltip('聊天菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除聊天'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(repository.deletedSessionIds, contains(1));
    expect(find.text('导数冲刺'), findsOneWidget);
  });
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

class _FakeAuthRepository extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<UserProfile?> getCurrentUserProfile() async => _testUser;
}

class _FakeLlmConfigRepository extends LlmConfigRepository {
  @override
  Future<LlmProviderConfig?> getByUserId(int userId) async => _testConfig;
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
  @override
  Future<List<KnowledgeContextSource>> search({
    required int userId,
    required String query,
    int? libraryId,
    int limit = 6,
  }) async {
    return const <KnowledgeContextSource>[];
  }
}

class _FakeAiChatRepository extends AiChatRepository {
  _FakeAiChatRepository() {
    sessions.add(
      AiChatSessionRecord(
        id: 1,
        userId: _testUser.id,
        title: '函数复习',
        lastMessagePreview: '先看定义',
        createdAt: DateTime.utc(2026, 5, 29, 8),
        updatedAt: DateTime.utc(2026, 5, 29, 8, 10),
      ),
    );
    messages[1] = [
      AiChatMessageRecord(
        id: 1,
        sessionId: 1,
        role: AiChatMessageRole.assistant,
        content: '先看定义',
        provider: 'minimax',
        model: 'MiniMax-M2.7',
        createdAt: DateTime.utc(2026, 5, 29, 8, 10),
      ),
    ];
  }

  final sessions = <AiChatSessionRecord>[];
  final messages = <int, List<AiChatMessageRecord>>{};
  final deletedSessionIds = <int>[];
  int _nextSessionId = 2;
  int _nextMessageId = 2;

  @override
  Future<AiChatSessionRecord> createSession({
    required int userId,
    required String title,
  }) async {
    final now = DateTime.utc(2026, 5, 29, 9, _nextSessionId);
    final session = AiChatSessionRecord(
      id: _nextSessionId++,
      userId: userId,
      title: title,
      lastMessagePreview: '',
      createdAt: now,
      updatedAt: now,
    );
    sessions.insert(0, session);
    messages[session.id] = [];
    return session;
  }

  @override
  Future<List<AiChatSessionRecord>> fetchSessions({
    required int userId,
    int limit = 100,
  }) async {
    return sessions
        .where((session) => session.userId == userId)
        .toList(growable: false);
  }

  @override
  Future<List<AiChatMessageRecord>> fetchMessages({
    required int sessionId,
    int limit = 100,
  }) async {
    return List<AiChatMessageRecord>.from(messages[sessionId] ?? const []);
  }

  @override
  Future<void> renameSession({
    required int userId,
    required int sessionId,
    required String title,
  }) async {
    final index = sessions.indexWhere((item) => item.id == sessionId);
    sessions[index] = sessions[index].copyWith(title: title);
  }

  @override
  Future<void> deleteSession({
    required int userId,
    required int sessionId,
  }) async {
    deletedSessionIds.add(sessionId);
    sessions.removeWhere((item) => item.id == sessionId);
    messages.remove(sessionId);
  }

  @override
  Future<AiChatMessageRecord> appendMessage({
    required int sessionId,
    required String role,
    required String content,
    String? provider,
    String? model,
  }) async {
    final message = AiChatMessageRecord(
      id: _nextMessageId++,
      sessionId: sessionId,
      role: role,
      content: content,
      provider: provider,
      model: model,
      createdAt: DateTime.utc(2026, 5, 29, 9, _nextMessageId),
    );
    messages.putIfAbsent(sessionId, () => []).add(message);
    return message;
  }

  @override
  Future<void> touchSessionPreview({
    required int sessionId,
    required String preview,
  }) async {
    final index = sessions.indexWhere((item) => item.id == sessionId);
    sessions[index] = sessions[index].copyWith(
      lastMessagePreview: preview,
      updatedAt: DateTime.utc(2026, 5, 29, 9, _nextSessionId),
    );
  }
}
