import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/agent/agent_task_executor.dart';
import 'package:pxt1/agent/eclaw_context.dart';
import 'package:pxt1/agent/eclaw_planner.dart';
import 'package:pxt1/agent/eclaw_tool_registry.dart';
import 'package:pxt1/database/agent_task_repository.dart';
import 'package:pxt1/database/ai_chat_repository.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_context_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase database;
  late int userId, libraryId, recordId;
  late AiChatRepository chats;
  setUp(() async {
    database = await AppDatabase.openForTesting(databaseFactoryFfi);
    final user = await AuthRepository(
      database: database,
    ).register(username: 'eclaw-test', password: 'offline-test');
    userId = user.userId!;
    libraryId = (await KnowledgeLibraryRepository(
      database: database,
    ).fetchLibraries(userId)).single.id;
    final document = await SourceDocumentRepository(database: database)
        .createSourceDocument(
          userId: userId,
          libraryId: libraryId,
          title: '高等数学函数与极限.pdf',
          sourceType: 'pdf_document',
          imagePath: 'fixture.pdf',
        );
    recordId = document.importRecordId!;
    chats = AiChatRepository(database: database);
  });
  tearDown(() async => (await database.database).close());

  test(
    'legacy provider and content survive schema consistency repair',
    () async {
      final session = await chats.createSession(
        userId: userId,
        title: '旧 QSClaw 会话',
      );
      final message = await chats.appendMessage(
        sessionId: session.id,
        role: 'assistant',
        content: '旧回复',
        provider: 'qsclaw',
        model: 'app-tools',
      );
      await database.ensureSchemaReady();
      final restored = (await chats.fetchMessages(
        sessionId: session.id,
      )).single;
      expect(restored.id, message.id);
      expect(restored.content, '旧回复');
      expect(restored.provider, 'qsclaw');
    },
  );

  test(
    'cancel before collection confirmation leaves documents and libraries unchanged',
    () async {
      final registry = EClawToolRegistry(database: database);
      final repository = AgentTaskRepository(database: database);
      final executor = AgentTaskExecutor(
        registry: registry,
        repository: repository,
      );
      final session = await chats.createSession(userId: userId, title: '整理');
      final steps = await EClawPlanner().plan(
        '把所有高等数学 PDF 整理到高等数学知识库',
        const EClawContext(),
        registry,
      );
      final task = await repository.create(
        userId: userId,
        sessionId: session.id,
        requestKey: 'cancel',
        command: '整理',
        context: const EClawContext(),
        steps: steps,
      );
      await executor.run(task);
      expect(task.status, 'waiting_confirmation');
      expect(
        await KnowledgeLibraryRepository(
          database: database,
        ).fetchLibraries(userId),
        hasLength(1),
      );
      await repository.cancel(userId, task.id);
      await executor.run(task, confirm: true);
      final db = await database.database;
      expect(
        (await db.query(
          'import_records',
          where: 'id=?',
          whereArgs: [recordId],
        )).single['library_id'],
        libraryId,
      );
      expect(
        await KnowledgeLibraryRepository(
          database: database,
        ).fetchLibraries(userId),
        hasLength(1),
      );
    },
  );

  test(
    'confirmed collection checkpoints survive reopening and undo restores ownership',
    () async {
      final registry = EClawToolRegistry(database: database);
      final repository = AgentTaskRepository(database: database);
      final executor = AgentTaskExecutor(
        registry: registry,
        repository: repository,
      );
      final session = await chats.createSession(userId: userId, title: '整理');
      final steps = await EClawPlanner().plan(
        '把所有高等数学 PDF 整理到高等数学知识库',
        const EClawContext(),
        registry,
      );
      final task = await repository.create(
        userId: userId,
        sessionId: session.id,
        requestKey: 'move',
        command: '整理',
        context: const EClawContext(),
        steps: steps,
      );
      await executor.run(task);
      await executor.run(task, confirm: true);
      expect(task.status, 'completed');
      final reopened = (await repository.get(userId, task.id))!;
      await AgentTaskExecutor(
        registry: registry,
        repository: repository,
      ).run(reopened);
      expect(
        await KnowledgeLibraryRepository(
          database: database,
        ).fetchLibraries(userId),
        hasLength(2),
      );
      final result = task.steps.last.result;
      await registry.run(
        'undo_document_move',
        EClawToolCall(
          userId: userId,
          context: const EClawContext(),
          args: {'operationKey': result['undoKey']},
          operationKey: 'undo',
        ),
        confirmed: true,
      );
      final db = await database.database;
      expect(
        (await db.query(
          'import_records',
          where: 'id=?',
          whereArgs: [recordId],
        )).single['library_id'],
        libraryId,
      );
    },
  );

  test(
    'foreign library IDs are rejected rather than widening retrieval',
    () async {
      final other = await AuthRepository(
        database: database,
      ).register(username: 'other', password: 'offline-test');
      final foreign = (await KnowledgeLibraryRepository(
        database: database,
      ).fetchLibraries(other.userId!)).single.id;
      await expectLater(
        KnowledgeContextRepository(
          database: database,
        ).search(userId: userId, query: '函数', knowledgeBaseId: foreign),
        throwsStateError,
      );
    },
  );
}
