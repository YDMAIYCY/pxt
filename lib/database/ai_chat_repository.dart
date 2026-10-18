import 'app_database.dart';
import 'models/ai_chat_records.dart';

// ========== AI Chat 仓库 ==========
// 管理聊天会话和消息的持久化，供聊天页做历史回溯。

class AiChatRepository {
  AiChatRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<AiChatSessionRecord> createSession({
    required int userId,
    required String title,
  }) async {
    final normalizedTitle = _normalizeTitle(title);
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final sessionId = await db.insert(AppDatabase.tableAiChatSessions, {
      'user_id': userId,
      'title': normalizedTitle,
      'last_message_preview': '',
      'created_at': now,
      'updated_at': now,
    });

    final session = await _findSessionById(
      userId: userId,
      sessionId: sessionId,
    );
    if (session == null) {
      throw StateError('AI Chat 会话创建后读取失败');
    }
    return session;
  }

  Future<List<AiChatSessionRecord>> fetchSessions({
    required int userId,
    int limit = 100,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableAiChatSessions,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC, id DESC',
      limit: limit,
    );

    return rows.map(AiChatSessionRecord.fromMap).toList(growable: false);
  }

  Future<List<AiChatMessageRecord>> fetchMessages({
    required int sessionId,
    int limit = 100,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableAiChatMessages,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );

    return rows.map(AiChatMessageRecord.fromMap).toList(growable: false);
  }

  Future<void> renameSession({
    required int userId,
    required int sessionId,
    required String title,
  }) async {
    final normalizedTitle = _normalizeTitle(title);
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final updated = await db.update(
      AppDatabase.tableAiChatSessions,
      {'title': normalizedTitle, 'updated_at': now},
      where: 'id = ? AND user_id = ?',
      whereArgs: [sessionId, userId],
    );
    if (updated == 0) {
      throw StateError('聊天不存在或无权重命名');
    }
  }

  Future<void> deleteSession({
    required int userId,
    required int sessionId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final deleted = await db.delete(
      AppDatabase.tableAiChatSessions,
      where: 'id = ? AND user_id = ?',
      whereArgs: [sessionId, userId],
    );
    if (deleted == 0) {
      throw StateError('聊天不存在或无权删除');
    }
  }

  Future<AiChatMessageRecord> appendMessage({
    required int sessionId,
    required String role,
    required String content,
    String? provider,
    String? model,
  }) async {
    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
      throw ArgumentError('聊天内容不能为空');
    }

    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final messageId = await db.insert(AppDatabase.tableAiChatMessages, {
      'session_id': sessionId,
      'role': AiChatMessageRole.normalize(role),
      'content': normalizedContent,
      'provider': provider?.trim(),
      'model': model?.trim(),
      'created_at': now,
    });

    final rows = await db.query(
      AppDatabase.tableAiChatMessages,
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('AI Chat 消息写入后读取失败');
    }
    return AiChatMessageRecord.fromMap(rows.first);
  }

  Future<void> touchSessionPreview({
    required int sessionId,
    required String preview,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      AppDatabase.tableAiChatSessions,
      {
        'last_message_preview': _normalizePreview(preview),
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<AiChatSessionRecord?> _findSessionById({
    required int userId,
    required int sessionId,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableAiChatSessions,
      where: 'id = ? AND user_id = ?',
      whereArgs: [sessionId, userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return AiChatSessionRecord.fromMap(rows.first);
  }

  String _normalizeTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('聊天标题不能为空');
    }
    return trimmed.length > 30 ? trimmed.substring(0, 30) : trimmed;
  }

  String _normalizePreview(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed;
  }
}
