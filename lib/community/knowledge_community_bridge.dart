import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../database/auth_repository.dart';
import '../learning/learning_events.dart';
import 'cloud_backend.dart';
import 'cloud_identity_repository.dart';
import 'community_repository.dart';

class KnowledgeCommunityBridge {
  KnowledgeCommunityBridge({
    AppDatabase? database,
    CloudIdentityRepository? identity,
  }) : _db = database ?? AppDatabase.instance,
       _identity = identity;
  final AppDatabase _db;
  final CloudIdentityRepository? _identity;
  Future<List<Map<String, Object?>>> shareableCards() async {
    final user = await AuthRepository(database: _db).getCurrentUserProfile();
    if (user == null) throw const CloudFailure('请先登录本地账号');
    return (await _db.database).rawQuery(
      '''SELECT k.id,k.title,k.content,k.document_id FROM knowledge_cards k
      JOIN source_documents s ON s.id=k.document_id WHERE s.user_id=? ORDER BY k.id DESC LIMIT 100''',
      [user.id],
    );
  }

  /// The caller passes only the community text explicitly selected by the user.
  Future<int> saveToLibrary({
    required Json question,
    Json? answer,
    required int libraryId,
  }) async {
    final user = await AuthRepository(database: _db).getCurrentUserProfile();
    if (user == null) throw const CloudFailure('请先登录本地账号');
    final uuid = await (_identity ?? CloudIdentityRepository(database: _db))
        .requireLinked();
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await _db.database;
    final documentId = await db.transaction((txn) async {
      if ((await txn.query(
        'knowledge_libraries',
        where: 'id=? AND user_id=?',
        whereArgs: [libraryId, user.id],
      )).isEmpty) {
        throw const CloudFailure('请选择自己的知识库');
      }
      final old = await txn.query(
        'community_knowledge_links',
        where: 'user_id=? AND question_id=? AND answer_id IS ?',
        whereArgs: [user.id, question['id'], answer?['id']],
      );
      if (old.isNotEmpty) return old.first['document_id'] as int;
      final title = question['title'] as String;
      final content =
          '${question['body']}\n\n${answer == null ? '' : '回答：\n${answer['body']}\n\n'}社区来源：问题 ${question['id']}${answer == null ? '' : ' / 回答 ${answer['id']}'}';
      final recordId = await txn.insert('import_records', {
        'user_id': user.id,
        'library_id': libraryId,
        'operation_id':
            'community:${question['id']}:${answer?['id'] ?? 'question'}',
        'title': title,
        'tags_json': '[]',
        'created_at': now,
        'updated_at': now,
      });
      final id = await txn.insert('source_documents', {
        'user_id': user.id,
        'library_id': libraryId,
        'import_record_id': recordId,
        'source_type': 'community',
        'image_path': '',
        'original_title': title,
        'ocr_status': 'completed',
        'created_at': now,
      });
      await txn.insert('ocr_texts', {
        'document_id': id,
        'raw_text': content,
        'final_text': content,
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('knowledge_cards', {
        'document_id': id,
        'title': title,
        'content': content,
        'created_at': now,
      });
      await txn.insert('community_knowledge_links', {
        'user_id': user.id,
        'auth_uuid': uuid,
        'question_id': question['id'],
        'answer_id': answer?['id'],
        'document_id': id,
        'created_at': now,
      });
      return id;
    });
    LearningEvents.notify();
    return documentId;
  }

  Future<void> linkPublishedQuestion(String questionId, int documentId) async {
    final user = await AuthRepository(database: _db).getCurrentUserProfile();
    if (user == null) throw const CloudFailure('请登录');
    final uuid = await (_identity ?? CloudIdentityRepository(database: _db))
        .requireLinked();
    final db = await _db.database;
    if ((await db.query(
      'source_documents',
      where: 'id=? AND user_id=?',
      whereArgs: [documentId, user.id],
    )).isEmpty) {
      throw const CloudFailure('无法引用其他用户的资料');
    }
    await db.insert('community_knowledge_links', {
      'user_id': user.id,
      'auth_uuid': uuid,
      'question_id': questionId,
      'document_id': documentId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> linksForRecord(
    int userId,
    int recordId,
  ) async => (await _db.database).rawQuery(
    '''SELECT c.* FROM community_knowledge_links c JOIN source_documents d ON d.id=c.document_id
      WHERE c.user_id=? AND d.user_id=? AND d.import_record_id=? ORDER BY c.id DESC''',
    [userId, userId, recordId],
  );
}
