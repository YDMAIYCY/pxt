import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../ocr/ocr_text_quality_evaluator.dart';
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

  Future<void> markOcrNeedsReview({
    required int documentId,
    required String message,
  }) {
    return _updateDocumentOcrStatus(
      documentId: documentId,
      status: SourceDocumentOcrStatus.needsReview,
      errorMessage: message.trim(),
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
    String? finalText,
    OcrQualityResult? quality,
    int? qualityScore,
    String? qualityLevel,
    List<String> qualityReasons = const <String>[],
    String language = 'zh-CN',
    String ocrStatus = SourceDocumentOcrStatus.success,
    String? ocrErrorMessage,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final normalizedRawText = rawText.trim();
    final normalizedCleanText = cleanText.trim();
    final normalizedFinalText = finalText?.trim();
    final resolvedQualityScore = quality?.score ?? qualityScore;
    final resolvedQualityLevel = quality?.level.value ?? qualityLevel?.trim();
    final resolvedQualityReasons = quality?.reasonValues ?? qualityReasons;

    await db.transaction((txn) async {
      final existing = await txn.query(
        AppDatabase.tableOcrTexts,
        columns: ['id', 'created_at'],
        where: 'document_id = ?',
        whereArgs: [documentId],
        limit: 1,
      );

      final values = <String, Object?>{
        'raw_text': normalizedRawText,
        'clean_text': normalizedCleanText,
        'final_text': normalizedFinalText == null || normalizedFinalText.isEmpty
            ? null
            : normalizedFinalText,
        'quality_score': resolvedQualityScore,
        'quality_level':
            resolvedQualityLevel == null || resolvedQualityLevel.isEmpty
            ? null
            : resolvedQualityLevel,
        'quality_reasons_json': jsonEncode(resolvedQualityReasons),
        'language': language.trim().isEmpty ? 'zh-CN' : language.trim(),
        'updated_at': now,
      };

      if (existing.isEmpty) {
        await txn.insert(AppDatabase.tableOcrTexts, {
          'document_id': documentId,
          ...values,
          'created_at': now,
        });
      } else {
        await txn.update(
          AppDatabase.tableOcrTexts,
          values,
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      }

      await _updateDocumentOcrStatusOnExecutor(
        txn,
        documentId: documentId,
        status: ocrStatus,
        errorMessage: ocrErrorMessage,
        updatedAt: now,
      );
    });
  }

  Future<void> saveFinalText({
    required int documentId,
    required String finalText,
    int? qualityScore,
    String? qualityLevel,
    List<String> qualityReasons = const <String>[],
  }) async {
    await _database.ensureSchemaReady();
    final normalizedFinalText = finalText.trim();
    if (normalizedFinalText.isEmpty) {
      throw ArgumentError.value(finalText, 'finalText', 'finalText 不能为空');
    }

    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final updated = await txn.update(
        AppDatabase.tableOcrTexts,
        {
          'final_text': normalizedFinalText,
          'quality_score': ?qualityScore,
          if (qualityLevel != null && qualityLevel.trim().isNotEmpty)
            'quality_level': qualityLevel.trim(),
          if (qualityReasons.isNotEmpty)
            'quality_reasons_json': jsonEncode(qualityReasons),
          'updated_at': now,
        },
        where: 'document_id = ?',
        whereArgs: [documentId],
      );

      if (updated == 0) {
        await txn.insert(AppDatabase.tableOcrTexts, {
          'document_id': documentId,
          'raw_text': normalizedFinalText,
          'clean_text': normalizedFinalText,
          'final_text': normalizedFinalText,
          'quality_score': qualityScore,
          'quality_level': qualityLevel,
          'quality_reasons_json': jsonEncode(qualityReasons),
          'language': 'zh-CN',
          'created_at': now,
          'updated_at': now,
        });
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
