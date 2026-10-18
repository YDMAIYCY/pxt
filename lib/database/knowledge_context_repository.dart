import 'app_database.dart';
import 'models/knowledge_context_source.dart';

class KnowledgeContextRepository {
  KnowledgeContextRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<List<KnowledgeContextSource>> search({
    required int userId,
    required String query,
    int? libraryId,
    int limit = 6,
  }) async {
    await _database.ensureSchemaReady();
    final terms = _termsOf(query);
    if (terms.isEmpty) {
      return const <KnowledgeContextSource>[];
    }

    final candidates = await _fetchCandidates(
      userId: userId,
      libraryId: libraryId,
      perTypeLimit: 80,
    );
    final ranked =
        candidates
            .map((source) => (_scoreSource(source, terms), source))
            .where((item) => item.$1 > 0)
            .toList(growable: false)
          ..sort((a, b) => b.$1.compareTo(a.$1));

    return ranked
        .take(limit)
        .map((item) => _trimSourceSnippet(item.$2, terms))
        .toList(growable: false);
  }

  Future<List<KnowledgeContextSource>> _fetchCandidates({
    required int userId,
    required int perTypeLimit,
    int? libraryId,
  }) async {
    final candidates = <KnowledgeContextSource>[];
    candidates.addAll(
      await _querySources(
        """
      SELECT r.document_id, COALESCE(documents.original_title, '') AS document_title,
        r.id AS source_id, r.title AS title, r.content AS snippet
      FROM learning_resources r JOIN source_documents documents ON documents.id = r.document_id
      WHERE documents.user_id = ?
        ${libraryId == null ? '' : 'AND documents.id IN (SELECT document_id FROM document_library_links WHERE library_id = ?)'}
        AND r.id IN (SELECT MAX(id) FROM learning_resources GROUP BY document_id, type)
      ORDER BY r.id DESC LIMIT ?
      """,
        _queryArgs(userId: userId, libraryId: libraryId, limit: perTypeLimit),
        'learning_resource',
        '学习资源',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT concepts.document_id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
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
                   LIMIT 6
                 ), '')
               ) AS snippet
        FROM ${AppDatabase.tableKnowledgeConcepts} concepts
        LEFT JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = concepts.document_id
        WHERE concepts.user_id = ?
          ${libraryId == null ? '' : 'AND concepts.id IN (SELECT cd.concept_id FROM concept_documents cd JOIN document_library_links dl ON dl.document_id = cd.document_id WHERE dl.library_id = ?)'}
        ORDER BY concepts.weakness_score DESC,
                 concepts.updated_at DESC,
                 concepts.id DESC
        LIMIT ?
        ''',
        _queryArgs(userId: userId, libraryId: libraryId, limit: perTypeLimit),
        KnowledgeContextSourceType.knowledgeGraph,
        '知识图谱',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT documents.id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               ocr.id AS source_id,
               COALESCE(ocr.final_text, ocr.clean_text, ocr.raw_text, '') AS snippet
        FROM ${AppDatabase.tableOcrTexts} ocr
        JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = ocr.document_id
        WHERE documents.user_id = ?
          ${libraryId == null ? '' : 'AND documents.id IN (SELECT document_id FROM document_library_links WHERE library_id = ?)'}
        ORDER BY ocr.updated_at DESC, ocr.id DESC
        LIMIT ?
        ''',
        _queryArgs(userId: userId, libraryId: libraryId, limit: perTypeLimit),
        KnowledgeContextSourceType.ocrText,
        'OCR文本',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT documents.id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               cards.id AS source_id,
               cards.title AS title,
               cards.content AS snippet
        FROM ${AppDatabase.tableKnowledgeCards} cards
        JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = cards.document_id
        WHERE documents.user_id = ?
          ${libraryId == null ? '' : 'AND documents.id IN (SELECT document_id FROM document_library_links WHERE library_id = ?)'}
        ORDER BY cards.id DESC
        LIMIT ?
        ''',
        _queryArgs(userId: userId, libraryId: libraryId, limit: perTypeLimit),
        KnowledgeContextSourceType.knowledgeCard,
        '知识卡片',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT documents.id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               outlines.id AS source_id,
               outlines.title AS title,
               outlines.outline_text AS snippet
        FROM ${AppDatabase.tableReviewOutlines} outlines
        JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = outlines.document_id
        WHERE documents.user_id = ?
          ${libraryId == null ? '' : 'AND documents.id IN (SELECT document_id FROM document_library_links WHERE library_id = ?)'}
        ORDER BY outlines.id DESC
        LIMIT ?
        ''',
        _queryArgs(userId: userId, libraryId: libraryId, limit: perTypeLimit),
        KnowledgeContextSourceType.reviewOutline,
        '复习提纲',
      ),
    );

    candidates.addAll(
      await _querySources(
        '''
        SELECT documents.id AS document_id,
               COALESCE(documents.original_title, '') AS document_title,
               questions.id AS source_id,
               questions.question_text AS title,
               COALESCE(questions.analysis_text, questions.answer_text, '') AS snippet
        FROM ${AppDatabase.tablePracticeQuestions} questions
        JOIN ${AppDatabase.tableSourceDocuments} documents
          ON documents.id = questions.document_id
        WHERE documents.user_id = ?
          ${libraryId == null ? '' : 'AND documents.id IN (SELECT document_id FROM document_library_links WHERE library_id = ?)'}
        ORDER BY questions.wrong_count DESC, questions.id DESC
        LIMIT ?
        ''',
        _queryArgs(userId: userId, libraryId: libraryId, limit: perTypeLimit),
        KnowledgeContextSourceType.practiceQuestion,
        '练习题',
      ),
    );

    return candidates;
  }

  List<Object?> _queryArgs({
    required int userId,
    required int limit,
    int? libraryId,
  }) {
    return libraryId == null
        ? <Object?>[userId, limit]
        : <Object?>[userId, libraryId, limit];
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
            title: (row['title'] as String?)?.trim() ?? '',
            snippet: (row['snippet'] as String?)?.trim() ?? '',
          ),
        )
        .where((source) => source.snippet.isNotEmpty || source.title.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _termsOf(String query) {
    final normalized = query.toLowerCase().replaceAll(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
      ' ',
    );
    final terms = normalized
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2)
        .toSet()
        .toList(growable: false);
    if (terms.isNotEmpty) {
      return terms;
    }

    final compact = query.trim();
    return compact.isEmpty ? const <String>[] : <String>[compact];
  }

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
