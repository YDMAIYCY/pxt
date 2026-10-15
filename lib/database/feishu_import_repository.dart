import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'app_database.dart';

class FeishuImportResult {
  const FeishuImportResult(this.created, this.updated, this.unchanged);
  final int created, updated, unchanged;
}

class FeishuImportRepository {
  FeishuImportRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;
  final AppDatabase _database;

  Future<Map<String, Object?>?> sourceInfo(int userId, int sourceId) async {
    final db = await _database.database;
    final rows = await db.query(
      'feishu_documents',
      where: 'user_id=? AND source_id=?',
      whereArgs: [userId, sourceId],
    );
    return rows.firstOrNull;
  }

  Future<FeishuImportResult> save(
    int userId,
    Map<String, dynamic> payload,
  ) async {
    final documents = await compute(
      _prepareDocuments,
      (payload['documents'] as List)
          .map((doc) => Map<String, dynamic>.from(doc as Map))
          .toList(),
    );
    if (documents.isEmpty) return const FeishuImportResult(0, 0, 0);
    final account = payload['account_id'] as String;
    final type = payload['container_type'] as String;
    final container = payload['container_id'] as String;
    final name = payload['container_name'] as String;
    if (account.isEmpty ||
        container.isEmpty ||
        !{'folder', 'wiki', 'document'}.contains(type)) {
      throw const FormatException('飞书来源信息不完整');
    }
    await _database.ensureSchemaReady();
    final db = await _database.database;
    return db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      var created = 0, updated = 0, unchanged = 0;
      final mappings = await txn.query(
        'feishu_containers',
        where:
            'user_id=? AND container_type=? AND container_id=?${type == 'document' ? ' AND library_id=?' : ''}',
        whereArgs: [
          userId,
          type,
          container,
          if (type == 'document') payload['target_library_id'],
        ],
      );
      final int libraryId;
      if (mappings.isEmpty) {
        final target = payload['target_library_id'] as int?;
        if (type == 'document' && target == null) {
          throw StateError('单篇文档必须先选择知识库');
        }
        if (target != null &&
            (await txn.query(
              'knowledge_libraries',
              where: 'id=? AND user_id=?',
              whereArgs: [target, userId],
            )).isEmpty) {
          throw StateError('无权访问目标知识库');
        }
        libraryId =
            target ??
            await txn.insert('knowledge_libraries', {
              'user_id': userId,
              'name': name,
              'description': '从飞书导入',
              'created_at': now,
              'updated_at': now,
            });
        await txn.insert('feishu_containers', {
          'user_id': userId,
          'account_id': account,
          'container_type': type,
          'container_id': container,
          'library_id': libraryId,
          'sync_mode': payload['sync_mode'] ?? 1,
          'selection_json': jsonEncode(
            payload['selection'] ??
                {
                  'kind': type,
                  'id': container,
                  'document_ids': documents
                      .map((d) => d['document_id'])
                      .toList(),
                },
          ),
        });
      } else {
        libraryId = mappings.single['library_id'] as int;
      }
      for (final doc in documents) {
        final remoteId = doc['document_id'] as String;
        final text = doc['text'] as String;
        final title = doc['title'] as String;
        final blocks = doc['_blocks_json'] as String;
        final hash = doc['_content_hash'] as String;
        final rows = await txn.query(
          'feishu_documents',
          where: 'user_id=? AND library_id=? AND document_id=?',
          whereArgs: [userId, libraryId, remoteId],
        );
        final int sourceId, recordId;
        var contentChanged = false;
        if (rows.isEmpty) {
          recordId = await txn.insert('import_records', {
            'user_id': userId,
            'library_id': libraryId,
            'operation_id': 'feishu:$libraryId:$account:$remoteId:$now',
            'title': title,
            'created_at': now,
            'updated_at': now,
          });
          sourceId = await txn.insert('source_documents', {
            'user_id': userId,
            'library_id': libraryId,
            'import_record_id': recordId,
            'source_type': 'feishu_docx',
            'image_path': '',
            'original_title': title,
            'ocr_status': 'success',
            'ocr_updated_at': now,
            'created_at': now,
          });
          created++;
        } else {
          final old = rows.single;
          sourceId = old['source_id'] as int;
          final source = (await txn.query(
            'source_documents',
            where: 'id=? AND user_id=?',
            whereArgs: [sourceId, userId],
          )).single;
          recordId = source['import_record_id'] as int;
          contentChanged = old['content_hash'] != hash;
          final changed = contentChanged || source['original_title'] != title;
          if (changed) {
            await txn.update(
              'source_documents',
              {
                'original_title': title,
                'ocr_status': 'success',
                'ocr_updated_at': now,
              },
              where: 'id=? AND user_id=?',
              whereArgs: [sourceId, userId],
            );
            await txn.update(
              'import_records',
              {'title': title, 'updated_at': now},
              where: 'id=? AND user_id=?',
              whereArgs: [recordId, userId],
            );
            updated++;
          } else {
            unchanged++;
          }
        }
        if (rows.isEmpty || contentChanged) {
          final existing = await txn.query(
            'ocr_texts',
            where: 'document_id=?',
            whereArgs: [sourceId],
          );
          final values = <String, Object?>{
            'raw_text': text,
            'clean_text': text,
            'final_text': text,
            'updated_at': now,
          };
          if (existing.isEmpty) {
            await txn.insert('ocr_texts', {
              'document_id': sourceId,
              ...values,
              'created_at': now,
            });
          } else {
            await txn.update(
              'ocr_texts',
              values,
              where: 'document_id=?',
              whereArgs: [sourceId],
            );
          }
        }
        final snapshot = await compute(_snapshot, {
          'document_id': sourceId,
          'title': title,
          'page': null,
          'text': text,
        });
        await txn.insert('record_source_versions', {
          'record_id': recordId,
          'fingerprint': snapshot['fingerprint'],
          'content': snapshot['content'],
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final metadata = <String, Object?>{
          'account_id': account,
          'node_token': doc['node_token'],
          'relative_path': doc['relative_path'] ?? title,
          'source_url': doc['source_url'] ?? 'https://feishu.cn/docx/$remoteId',
          'remote_modified_time': doc['modified_time']?.toString(),
          'revision_id': doc['revision_id'],
          'blocks_json': blocks,
          'content_hash': hash,
          'synced_at': now,
          'knowledge_needs_update': contentChanged
              ? 1
              : (rows.firstOrNull?['knowledge_needs_update'] ?? 0),
        };
        if (rows.isEmpty) {
          await txn.insert('feishu_documents', {
            'user_id': userId,
            'account_id': account,
            'document_id': remoteId,
            'source_id': sourceId,
            'library_id': libraryId,
            'container_type': type,
            'container_id': container,
            'node_token': doc['node_token'],
            ...metadata,
          });
        } else {
          // Preserve source IDs and all learning results when refreshing this library.
          await txn.update(
            'feishu_documents',
            metadata,
            where: 'user_id=? AND library_id=? AND document_id=?',
            whereArgs: [userId, libraryId, remoteId],
          );
        }
      }
      return FeishuImportResult(created, updated, unchanged);
    });
  }
}

List<Map<String, dynamic>> _prepareDocuments(
  List<Map<String, dynamic>> documents,
) => [
  for (final doc in documents)
    {
      ...doc,
      '_blocks_json': jsonEncode(doc['blocks']),
      '_content_hash': sha256
          .convert(
            utf8.encode(
              jsonEncode({'text': doc['text'], 'blocks': doc['blocks']}),
            ),
          )
          .toString(),
    },
];

Map<String, String> _snapshot(Map<String, dynamic> source) {
  final content = jsonEncode({
    'sources': [source],
  });
  return {
    'content': content,
    'fingerprint': sha256.convert(utf8.encode(content)).toString(),
  };
}
