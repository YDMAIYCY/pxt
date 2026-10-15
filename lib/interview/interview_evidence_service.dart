import '../database/app_database.dart';

class InterviewEvidence {
  const InterviewEvidence({
    required this.key,
    required this.sourceRecordId,
    required this.sourcePageId,
    required this.title,
    required this.content,
    required this.sourceKind,
    this.knowledgePointId,
  });
  final String key, title, content, sourceKind;
  final int sourceRecordId, sourcePageId;
  final int? knowledgePointId;
  bool get isOriginal => sourceKind == 'ocr';
  Map<String, Object?> toPrompt() => {
    'source_key': key,
    'record_id': sourceRecordId,
    'page_id': sourcePageId,
    'title': title,
    'kind': sourceKind,
    'knowledge_point_id': knowledgePointId,
    'evidence': content,
  };
}

class InterviewEvidenceService {
  InterviewEvidenceService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;
  final AppDatabase _database;
  Future<List<InterviewEvidence>> load({
    required int userId,
    required int libraryId,
    int? recordId,
    String mode = 'basic',
    int limit = 18,
  }) async {
    final db = await _database.database;
    if ((await db.query(
      'knowledge_libraries',
      where: 'id=? AND user_id=?',
      whereArgs: [libraryId, userId],
    )).isEmpty) {
      throw StateError('知识库不存在或无权访问');
    }
    if (recordId != null &&
        (await db.query(
          'import_records',
          where: 'id=? AND user_id=? AND library_id=?',
          whereArgs: [recordId, userId, libraryId],
        )).isEmpty) {
      throw StateError('导入记录不属于所选知识库');
    }
    final args = <Object?>[userId, libraryId, ?recordId];
    final scope =
        's.user_id=? AND r.user_id=s.user_id AND r.library_id=? ${recordId == null ? '' : 'AND r.id=?'}';
    final originals = await db.rawQuery(
      '''SELECT s.id page_id, r.id record_id,
      s.source_type source_type, r.title title, COALESCE(NULLIF(o.final_text,''), NULLIF(o.clean_text,''), o.raw_text) content,
      (SELECT c.id FROM knowledge_concepts c WHERE c.document_id=s.id AND c.user_id=s.user_id ORDER BY c.weakness_score DESC LIMIT 1) concept_id,
      COALESCE((SELECT MAX(c.weakness_score) FROM knowledge_concepts c WHERE c.document_id=s.id AND c.user_id=s.user_id),0) weakness_score,
      (SELECT COUNT(*) FROM practice_questions q WHERE q.document_id=s.id AND q.review_status='wrong') wrong_count
      FROM source_documents s JOIN import_records r ON r.id=s.import_record_id
      JOIN ocr_texts o ON o.document_id=s.id WHERE $scope AND s.ocr_status='success'
      ORDER BY ${mode == 'quick' ? 'wrong_count DESC, weakness_score DESC,' : ''} r.created_at DESC, s.page_number, s.id''',
      args,
    );
    final results = <InterviewEvidence>[];
    final originalPages = <int>{};
    final recordsWithPages = originals
        .where((r) => (r['content'] as String? ?? '').trim().isNotEmpty)
        .map((r) => r['record_id'])
        .toSet();
    for (final row in originals) {
      final text = (row['content'] as String? ?? '').trim();
      if (text.length < 12) continue;
      final page = row['page_id'] as int;
      // The PDF container often duplicates text already available on its pages.
      if (row['source_type'] == 'pdf_document' &&
          recordsWithPages.contains(row['record_id']) &&
          originals.where((o) => o['record_id'] == row['record_id']).length >
              1) {
        continue;
      }
      results.add(
        InterviewEvidence(
          key: 'ocr:$page',
          sourceRecordId: row['record_id'] as int,
          sourcePageId: page,
          title: row['title'] as String,
          content: text.length > 2400 ? text.substring(0, 2400) : text,
          sourceKind: 'ocr',
          knowledgePointId: row['concept_id'] as int?,
        ),
      );
      originalPages.add(page);
    }
    // Derived evidence is explicitly labelled and never presented as original OCR.
    for (final entry in {
      'knowledge_cards': 'title || char(10) || content',
      'review_outlines': 'title || char(10) || outline_text',
      'practice_questions':
          "question_text || char(10) || COALESCE(answer_text,'') || char(10) || COALESCE(analysis_text,'')",
    }.entries) {
      final rows = await db.rawQuery(
        'SELECT t.id result_id,s.id page_id,r.id record_id,r.title title, ${entry.value.split(' || ').map((part) => ['title', 'content', 'outline_text', 'question_text'].contains(part) ? 't.$part' : part).join(' || ')} content FROM ${entry.key} t JOIN source_documents s ON s.id=t.document_id JOIN import_records r ON r.id=s.import_record_id WHERE $scope ORDER BY t.id DESC',
        args,
      );
      for (final row in rows) {
        if (originalPages.contains(row['page_id'])) continue;
        final text = (row['content'] as String? ?? '').trim();
        if (text.length < 12) continue;
        results.add(
          InterviewEvidence(
            key: '${entry.key}:${row['result_id']}',
            sourceRecordId: row['record_id'] as int,
            sourcePageId: row['page_id'] as int,
            title: row['title'] as String,
            content: text.length > 1800 ? text.substring(0, 1800) : text,
            sourceKind: entry.key,
          ),
        );
      }
    }
    if (results.isEmpty) throw StateError('所选范围暂无可靠学习资料，请先完成 OCR 校对或保存知识成果。');
    return results.take(limit).toList();
  }
}
