import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models/ocr_text_record.dart';
import 'models/source_document_record.dart';

class OcrTextRepository {
  OcrTextRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<OcrTextRecord?> getByDocumentId(int documentId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableOcrTexts,
      where: 'document_id = ?',
      whereArgs: [documentId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return OcrTextRecord.fromMap(rows.first);
  }

  Future<void> markOcrPending({required int documentId}) {
    return _updateDocumentOcrStatus(
      documentId: documentId,
      status: SourceDocumentOcrStatus.pending,
      errorMessage: null,
    );
  }

  Future<void> markOcrProcessing({required int documentId}) {
    return _updateDocumentOcrStatus(
      documentId: documentId,
      status: SourceDocumentOcrStatus.processing,
      errorMessage: null,
    );
  }

  Future<void> markOcrFailed({
    required int documentId,
    required String errorMessage,
  }) {
    return _updateDocumentOcrStatus(
      documentId: documentId,
      status: SourceDocumentOcrStatus.failed,
      errorMessage: errorMessage.trim(),
    );
  }

  Future<void> upsertOcrText({
    required int documentId,
    required String rawText,
    required String cleanText,
    String language = 'zh-CN',
  }) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final existing = await txn.query(
        AppDatabase.tableOcrTexts,
        columns: ['id', 'created_at'],
        where: 'document_id = ?',
        whereArgs: [documentId],
        limit: 1,
      );

      final normalizedRawText = rawText.trim();
      final normalizedCleanText = cleanText.trim();

      if (existing.isEmpty) {
        await txn.insert(AppDatabase.tableOcrTexts, {
          'document_id': documentId,
          'raw_text': normalizedRawText,
          'clean_text': normalizedCleanText,
          'language': language.trim().isEmpty ? 'zh-CN' : language.trim(),
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await txn.update(
          AppDatabase.tableOcrTexts,
          {
            'raw_text': normalizedRawText,
            'clean_text': normalizedCleanText,
            'language': language.trim().isEmpty ? 'zh-CN' : language.trim(),
            'updated_at': now,
          },
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      }

      await _updateDocumentOcrStatusOnExecutor(
        txn,
        documentId: documentId,
        status: SourceDocumentOcrStatus.success,
        errorMessage: null,
        updatedAt: now,
      );
    });
  }

  Future<void> _updateDocumentOcrStatus({
    required int documentId,
    required String status,
    required String? errorMessage,
  }) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await _updateDocumentOcrStatusOnExecutor(
      db,
      documentId: documentId,
      status: status,
      errorMessage: errorMessage,
      updatedAt: now,
    );
  }

  Future<void> _updateDocumentOcrStatusOnExecutor(
    DatabaseExecutor db, {
    required int documentId,
    required String status,
    required String? errorMessage,
    required String updatedAt,
  }) async {
    await db.update(
      AppDatabase.tableSourceDocuments,
      {
        'ocr_status': status,
        'ocr_error_message': errorMessage,
        'ocr_updated_at': updatedAt,
      },
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }
}
