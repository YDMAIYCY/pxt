import 'dart:convert';
import '../agent/eclaw_context.dart';
import '../agent/eclaw_task.dart';
import 'app_database.dart';
import 'ai_chat_repository.dart';

class AgentTaskRepository {
  AgentTaskRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;
  final AppDatabase _database;
  Future<AgentTask> create({
    required int userId,
    required int sessionId,
    required String requestKey,
    required String command,
    required EClawContext context,
    required List<AgentTaskStep> steps,
  }) async {
    await _database.ensureSchemaReady();
    await AiChatRepository(database: _database).requireOwner(userId, sessionId);
    final db = await _database.database;
    final existing = await db.query(
      'agent_tasks',
      where: 'user_id=? AND session_id=? AND request_key=?',
      whereArgs: [userId, sessionId, requestKey],
    );
    if (existing.isNotEmpty) return _read(existing.single);
    final id = await db.insert('agent_tasks', {
      'user_id': userId,
      'session_id': sessionId,
      'request_key': requestKey,
      'command': command,
      'context_json': jsonEncode(context.toJson()),
      'steps_json': jsonEncode(steps.map((s) => s.toJson()).toList()),
      'status': 'pending',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return (await get(userId, id))!;
  }

  Future<AgentTask?> get(int userId, int id) async {
    final db = await _database.database;
    final rows = await db.query(
      'agent_tasks',
      where: 'id=? AND user_id=?',
      whereArgs: [id, userId],
    );
    return rows.isEmpty ? null : _read(rows.single);
  }

  Future<List<AgentTask>> forSession(int userId, int sessionId) async {
    await AiChatRepository(database: _database).requireOwner(userId, sessionId);
    final db = await _database.database;
    return (await db.query(
      'agent_tasks',
      where: 'user_id=? AND session_id=?',
      whereArgs: [userId, sessionId],
      orderBy: 'id ASC',
    )).map(_read).toList();
  }

  Future<bool> claim(int userId, int id) async {
    final db = await _database.database;
    return await db.rawUpdate(
          "UPDATE agent_tasks SET status='running' WHERE id=? AND user_id=? AND status IN ('pending','waiting_confirmation','failed') AND cancel_requested=0",
          [id, userId],
        ) ==
        1;
  }

  Future<void> save(AgentTask task) async {
    final db = await _database.database;
    await db.update(
      'agent_tasks',
      {
        'steps_json': jsonEncode(task.steps.map((s) => s.toJson()).toList()),
        'status': task.status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND user_id=?',
      whereArgs: [task.id, task.userId],
    );
  }

  Future<void> cancel(int userId, int id) async {
    final db = await _database.database;
    await db.rawUpdate(
      "UPDATE agent_tasks SET cancel_requested=1, status=CASE WHEN status='running' THEN status ELSE 'cancelled' END WHERE id=? AND user_id=? AND status!='completed'",
      [id, userId],
    );
  }

  AgentTask _read(Map<String, Object?> row) => AgentTask(
    id: row['id'] as int,
    userId: row['user_id'] as int,
    sessionId: row['session_id'] as int,
    command: row['command'] as String,
    context: EClawContext.fromJson(
      jsonDecode(row['context_json'] as String) as Map<String, dynamic>,
    ),
    steps: (jsonDecode(row['steps_json'] as String) as List)
        .map((s) => AgentTaskStep.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList(),
    status: row['status'] as String,
    cancelRequested: row['cancel_requested'] == 1,
  );
}
