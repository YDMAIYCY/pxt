import '../agent/eclaw_context.dart';
import 'app_database.dart';
import 'models/knowledge_context_source.dart';
import 'package:sqflite/sqflite.dart';

class KnowledgeContextRepository {
  KnowledgeContextRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  bool? _ftsAvailable;

  Future<List<KnowledgeContextSource>> search({
    required int userId,
    required String query,
    int? libraryId,
    int? knowledgeBaseId,
    int? importRecordId,
    int? documentId,
    int limit = 6,
  }) async {
    await _database.ensureSchemaReady();
    libraryId = knowledgeBaseId ?? libraryId;
    await validateScope(
      userId,
      EClawContext(
        knowledgeBaseId: libraryId,
        importRecordId: importRecordId,
        documentId: documentId,
      ),
    );
    final terms = _termsOf(query);
    if (terms.isEmpty) {
      if (query.trim().isEmpty) {
        final sources = await _fetchCandidates(
          userId: userId,
          libraryId: libraryId,
          importRecordId: importRecordId,
          documentId: documentId,
        );
        return sources
            .take(limit)
            .map((s) => _trimSourceSnippet(s, const []))
            .toList();
      }
      return const <KnowledgeContextSource>[];
    }

    final candidates = await _fetchCandidates(
      userId: userId,
      libraryId: libraryId,
      importRecordId: importRecordId,
      documentId: documentId,
    );
    final fullTextRanks = await _fullTextRanks(userId, candidates, terms);
    final ranked =
        candidates
            .asMap()
            .entries
            .map(
              (entry) => (
                _scoreSource(entry.value, terms).toDouble() +
                    (fullTextRanks[entry.key] == null
                        ? 0
                        : 60 / (60 + fullTextRanks[entry.key]!)),
                entry.value,
              ),
            )
            .where((item) => item.$1 > 0)
            .toList(growable: false)
          ..sort((a, b) => b.$1.compareTo(a.$1));

    final seen = <String>{};
    return ranked
        .where((item) => seen.add('${item.$2.sourceType}:${item.$2.sourceId}'))
        .take(limit)
        .map((item) => _trimSourceSnippet(item.$2, terms))
        .toList(growable: false);
  }

  Future<List<KnowledgeContextSource>> _fetchCandidates({
    required int userId,
    int? importRecordId,
    int? documentId,
    int? libraryId,
  }) async {
    final candidates = <KnowledgeContextSource>[];
    final scopeArgs = <Object?>[userId];
    var filter = 'documents.user_id = ?';
    if (libraryId != null) {
      filter += """ AND EXISTS (SELECT 1 FROM knowledge_libraries l
        WHERE l.id=documents.library_id AND l.user_id=documents.user_id AND l.id=?)""";
      scopeArgs.add(libraryId);
    }
    if (importRecordId != null) {
      filter += ' AND documents.import_record_id=?';
      scopeArgs.add(importRecordId);
    }
    if (documentId != null) {
      filter += ' AND documents.id=?';
      scopeArgs.add(documentId);
    }

    candidates.addAll(
      await _querySources(
        '''
        SELECT concepts.document_id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               documents.import_record_id AS record_id,
               documents.page_number AS page_number,
               concepts.id AS source_id,
               concepts.name AS title,
               TRIM(
                 COALESCE(concepts.summary, '') || char(10) ||
                 COALESCE(concepts.evidence_text, '') || char(10) ||
                 '掌握度 ' || concepts.mastery_score || ' / 薄弱 ' || concepts.weakness_score || char(10) ||
                 COALESCE((
                   SELECT GROUP_CONCAT(
                     links.relation_label || ': ' || linked.name,
                     char(10)
                   )
                   FROM ${AppDatabase.tableKnowledgeConceptLinks} links
                   JOIN ${AppDatabase.tableKnowledgeConcepts} linked
                     ON linked.id = links.to_concept_id
                   WHERE links.from_concept_id = concepts.id
                     AND linked.user_id=concepts.user_id
                     AND linked.document_id=concepts.document_id
                   LIMIT 6
                 ), '')
               ) AS snippet
        FROM ${AppDatabase.tableKnowledgeConcepts} concepts
        LEFT JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = concepts.document_id
        WHERE concepts.user_id = documents.user_id AND $filter
        ORDER BY concepts.weakness_score DESC,
                 concepts.updated_at DESC,
                 concepts.id DESC
        ''',
        scopeArgs,
        KnowledgeContextSourceType.knowledgeGraph,
        '知识图谱',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT documents.id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               documents.import_record_id AS record_id,
               documents.page_number AS page_number,
               ocr.id AS source_id,
               COALESCE(ocr.final_text, ocr.clean_text, ocr.raw_text, '') AS snippet
        FROM ${AppDatabase.tableOcrTexts} ocr
        JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = ocr.document_id
        WHERE $filter
        ORDER BY ocr.updated_at DESC, ocr.id DESC
        ''',
        scopeArgs,
        KnowledgeContextSourceType.ocrText,
        'OCR文本',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT documents.id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               documents.import_record_id AS record_id,
               documents.page_number AS page_number,
               cards.id AS source_id,
               cards.title AS title,
               cards.content AS snippet
        FROM ${AppDatabase.tableKnowledgeCards} cards
        JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = cards.document_id
        WHERE $filter
        ORDER BY cards.id DESC
        ''',
        scopeArgs,
        KnowledgeContextSourceType.knowledgeCard,
        '知识卡片',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT documents.id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               documents.import_record_id AS record_id,
               documents.page_number AS page_number,
               outlines.id AS source_id,
               outlines.title AS title,
               outlines.outline_text AS snippet
        FROM ${AppDatabase.tableReviewOutlines} outlines
        JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = outlines.document_id
        WHERE $filter
        ORDER BY outlines.id DESC
        ''',
        scopeArgs,
        KnowledgeContextSourceType.reviewOutline,
        '复习提纲',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT documents.id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               documents.import_record_id AS record_id,
               documents.page_number AS page_number,
               questions.id AS source_id,
               questions.question_text AS title,
               COALESCE(questions.analysis_text, questions.answer_text, '') AS snippet
        FROM ${AppDatabase.tablePracticeQuestions} questions
        JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = questions.document_id
        WHERE $filter
        ORDER BY questions.wrong_count DESC, questions.id DESC
        ''',
        scopeArgs,
        KnowledgeContextSourceType.practiceQuestion,
        '练习题',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
      SELECT documents.id document_id, documents.original_title document_title,
        documents.import_record_id record_id, documents.page_number,
        s.id source_id, n.display_name title,
        COALESCE(s.evidence_text,n.description,'') snippet
      FROM graph_node_sources s JOIN graph_nodes n ON n.id=s.node_id
      JOIN source_documents documents ON documents.id=s.source_document_id
      WHERE $filter AND s.user_id=documents.user_id AND n.user_id=documents.user_id
        AND n.status!='invalid' AND n.merged_into_node_id IS NULL
      ''',
        scopeArgs,
        KnowledgeContextSourceType.knowledgeGraph,
        '知识图谱',
      ),
    );
    candidates.addAll(
      await _querySources(
        '''
      SELECT documents.id document_id, documents.original_title document_title,
        documents.import_record_id record_id, documents.page_number,
        t.id source_id, '' title, t.mindmap_text snippet
      FROM mindmap_texts t JOIN source_documents documents ON documents.id=t.document_id
      WHERE $filter''',
        scopeArgs,
        'structured_knowledge',
        '结构化知识',
      ),
    );
    return candidates.expand(_chunks).toList(growable: false);
  }

  Iterable<KnowledgeContextSource> _chunks(KnowledgeContextSource s) sync* {
    if (s.snippet.length <= 520) {
      yield s;
      return;
    }
    for (var start = 0; start < s.snippet.length; start += 420) {
      final end = (start + 520).clamp(0, s.snippet.length);
      yield KnowledgeContextSource(
        documentId: s.documentId,
        documentTitle: s.documentTitle,
        sourceType: s.sourceType,
        sourceLabel: s.sourceLabel,
        title: s.title,
        snippet: s.snippet.substring(start, end),
        sourceId: s.sourceId,
        recordId: s.recordId,
        pageNumber: s.pageNumber,
        blockStart: start,
      );
    }
  }

  Future<Map<int, int>> _fullTextRanks(
    int userId,
    List<KnowledgeContextSource> sources,
    List<String> terms,
  ) async {
    if (_ftsAvailable == false || sources.isEmpty || terms.isEmpty) return {};
    final db = await _database.database;
    try {
      await db.execute(
        '''CREATE VIRTUAL TABLE IF NOT EXISTS eclaw_fts USING fts5(
        user_id UNINDEXED, candidate_id UNINDEXED, content, tokenize='unicode61')''',
      );
      _ftsAvailable = true;
      return await db.transaction((txn) async {
        // Cache only scoped candidates; stale or another user's entries can never
        // map to the returned evidence. Rebuilding reflects edits immediately.
        await txn.delete('eclaw_fts', where: 'user_id=?', whereArgs: [userId]);
        final batch = txn.batch();
        for (var i = 0; i < sources.length; i++) {
          final s = sources[i];
          batch.insert('eclaw_fts', {
            'user_id': userId,
            'candidate_id': i,
            'content': tokens(
              '${s.title} ${s.documentTitle} ${s.snippet}',
            ).join(' '),
          });
        }
        await batch.commit(noResult: true);
        final rows = await txn.rawQuery(
          '''SELECT candidate_id FROM eclaw_fts
          WHERE eclaw_fts MATCH ? AND user_id=? ORDER BY bm25(eclaw_fts) LIMIT 100''',
          [terms.map((t) => '"$t"').join(' OR '), userId],
        );
        return {
          for (var i = 0; i < rows.length; i++)
            rows[i]['candidate_id'] as int: i + 1,
        };
      });
    } on DatabaseException catch (e) {
      if (!e.toString().contains('no such module: fts5')) rethrow;
      _ftsAvailable = false;
      return {};
    }
  }

  Future<List<KnowledgeContextSource>> _querySources(
    String sql,
    List<Object?> args,
    String sourceType,
    String sourceLabel,
  ) async {
    final db = await _database.database;
    final rows = await db.rawQuery(sql, args);
    return rows
        .map(
          (row) => KnowledgeContextSource(
            documentId: row['document_id'] as int,
            documentTitle: _documentTitle(row),
            sourceType: sourceType,
            sourceLabel: sourceLabel,
            sourceId: _readNullableInt(row['source_id']),
            recordId: _readNullableInt(row['record_id']),
            pageNumber: _readNullableInt(row['page_number']),
            title: (row['title'] as String?)?.trim() ?? '',
            snippet: (row['snippet'] as String?)?.trim() ?? '',
          ),
        )
        .where((source) => source.snippet.isNotEmpty || source.title.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> validateScope(int userId, EClawContext scope) async {
    final db = await _database.database;
    for (final item in [
      ('knowledge_libraries', scope.knowledgeBaseId),
      ('import_records', scope.importRecordId),
      ('source_documents', scope.documentId),
      ('interview_sessions', scope.interviewSessionId),
    ]) {
      if (item.$2 == null) continue;
      final rows = await db.query(
        item.$1,
        columns: ['id'],
        where: 'id=? AND user_id=?',
        whereArgs: [item.$2, userId],
      );
      if (rows.isEmpty) throw StateError('资料范围不存在或无权访问');
    }
    if (scope.importRecordId != null && scope.knowledgeBaseId != null) {
      final record = await db.query(
        'import_records',
        columns: ['id'],
        where: 'id=? AND user_id=? AND library_id=?',
        whereArgs: [scope.importRecordId, userId, scope.knowledgeBaseId],
      );
      if (record.isEmpty) throw StateError('记录已移出当前知识库，请刷新资料范围');
    }
    if (scope.documentId != null) {
      final rows = await db.query(
        'source_documents',
        columns: ['library_id', 'import_record_id'],
        where: 'id=? AND user_id=?',
        whereArgs: [scope.documentId, userId],
      );
      if ((scope.knowledgeBaseId != null &&
              rows.single['library_id'] != scope.knowledgeBaseId) ||
          (scope.importRecordId != null &&
              rows.single['import_record_id'] != scope.importRecordId)) {
        throw StateError('页面上下文与资料范围不一致，请刷新');
      }
    }
  }

  static List<String> tokens(String text) {
    final result = <String>{};
    for (final match in RegExp(
      r'[a-z0-9]+|[\u4e00-\u9fff]+',
    ).allMatches(text.toLowerCase())) {
      final term = match.group(0)!;
      if (RegExp(r'^[a-z0-9]+$').hasMatch(term)) {
        result.add(term);
        continue;
      }
      if (term.length <= 18) result.add(term);
      for (var i = 0; i < term.length - 1; i++) {
        final gram = term.substring(i, i + 2);
        if (!const {
          '什么',
          '是什',
          '怎么',
          '如何',
          '帮我',
          '一下',
          '可以',
          '我的',
          '资料',
          '知识',
          '解释',
          '请问',
          '能帮',
        }.contains(gram)) {
          result.add(gram);
        }
      }
    }
    return result.toList();
  }

  List<String> _termsOf(String query) => tokens(query);

  int _scoreSource(KnowledgeContextSource source, List<String> terms) {
    final title = source.title.toLowerCase();
    final snippet = source.snippet.toLowerCase();
    var score = 0;
    for (final term in terms) {
      if (title.contains(term)) {
        score += 4;
      }
      if (snippet.contains(term)) {
        score += 2;
      }
      if (source.documentTitle.toLowerCase().contains(term)) {
        score += 1;
      }
    }
    return score;
  }

  KnowledgeContextSource _trimSourceSnippet(
    KnowledgeContextSource source,
    List<String> terms,
  ) {
    final text = source.snippet.trim();
    if (text.length <= 360) {
      return source;
    }

    final lower = text.toLowerCase();
    final firstHit = terms
        .map((term) => lower.indexOf(term))
        .where((index) => index >= 0)
        .fold<int?>(
          null,
          (best, index) => best == null || index < best ? index : best,
        );
    final center = firstHit ?? 0;
    final start = (center - 140).clamp(0, text.length).toInt();
    final end = (start + 360).clamp(0, text.length).toInt();
    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';
    return KnowledgeContextSource(
      documentId: source.documentId,
      documentTitle: source.documentTitle,
      sourceType: source.sourceType,
      sourceLabel: source.sourceLabel,
      sourceId: source.sourceId,
      recordId: source.recordId,
      pageNumber: source.pageNumber,
      blockStart: (source.blockStart ?? 0) + start,
      title: source.title,
      snippet: '$prefix${text.substring(start, end)}$suffix',
    );
  }

  String _documentTitle(Map<String, Object?> row) {
    final title = (row['document_title'] as String?)?.trim();
    return title == null || title.isEmpty ? '未命名资料' : title;
  }

  int? _readNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
