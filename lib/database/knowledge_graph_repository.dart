import 'app_database.dart';
import 'models/ai_result_records.dart';
import 'models/knowledge_graph_records.dart';

class KnowledgeConceptDraft {
  const KnowledgeConceptDraft({
    required this.name,
    required this.summary,
    required this.evidenceText,
    required this.masteryScore,
    required this.weaknessScore,
  });

  final String name;
  final String summary;
  final String evidenceText;
  final int masteryScore;
  final int weaknessScore;
}

class KnowledgeConceptLinkDraft {
  const KnowledgeConceptLinkDraft({
    required this.fromName,
    required this.toName,
    required this.relationLabel,
  });

  final String fromName;
  final String toName;
  final String relationLabel;
}

class KnowledgeGraphDraft {
  const KnowledgeGraphDraft({required this.concepts, required this.links});

  final List<KnowledgeConceptDraft> concepts;
  final List<KnowledgeConceptLinkDraft> links;
}

class KnowledgeNextBestAction {
  const KnowledgeNextBestAction({
    required this.concept,
    required this.documentTitle,
    required this.actionLabel,
    required this.reason,
    required this.priorityScore,
  });

  final KnowledgeConceptRecord concept;
  final String documentTitle;
  final String actionLabel;
  final String reason;
  final int priorityScore;
}

class KnowledgeGraphRepository {
  KnowledgeGraphRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<({int userId, int? libraryId})?> findDocumentScope(
    int documentId,
  ) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableSourceDocuments,
      columns: ['user_id', 'library_id'],
      where: 'id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return (
      userId: rows.first['user_id'] as int,
      libraryId: rows.first['library_id'] as int?,
    );
  }

  Future<void> replaceGraphForDocument({
    required int userId,
    required int documentId,
    required KnowledgeGraphDraft draft,
    int? libraryId,
    String sourceType = 'generated',
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        'concept_documents',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
      final conceptIdsByName = <String, int>{};
      for (final concept in draft.concepts) {
        final name = concept.name.trim();
        if (name.isEmpty || conceptIdsByName.containsKey(name)) continue;
        final existing = await txn.rawQuery(
          'SELECT id FROM knowledge_concepts WHERE user_id = ? AND LOWER(TRIM(name)) = LOWER(?) ORDER BY id LIMIT 1',
          [userId, name],
        );
        final conceptId = existing.isNotEmpty
            ? existing.first['id'] as int
            : await txn.insert(AppDatabase.tableKnowledgeConcepts, {
                'user_id': userId,
                'library_id': libraryId,
                'document_id': documentId,
                'name': name,
                'summary': concept.summary.trim(),
                'evidence_text': concept.evidenceText.trim(),
                'source_type': sourceType,
                'source_id': null,
                'mastery_score': 0,
                'weakness_score': 0,
                'created_at': now,
                'updated_at': now,
              });
        await txn.insert('concept_documents', {
          'concept_id': conceptId,
          'document_id': documentId,
        });
        conceptIdsByName[name] = conceptId;
      }

      final seenLinks = <String>{};
      for (final link in draft.links) {
        final fromId = conceptIdsByName[link.fromName.trim()];
        final toId = conceptIdsByName[link.toName.trim()];
        if (fromId == null || toId == null || fromId == toId) {
          continue;
        }
        final relation = link.relationLabel.trim().isEmpty
            ? '相关'
            : link.relationLabel.trim();
        final key = '$fromId->$toId:$relation';
        if (!seenLinks.add(key)) {
          continue;
        }
        final prior = await txn.query(
          AppDatabase.tableKnowledgeConceptLinks,
          columns: ['id'],
          where:
              'user_id = ? AND from_concept_id = ? AND to_concept_id = ? AND relation_label = ?',
          whereArgs: [userId, fromId, toId, relation],
        );
        if (prior.isNotEmpty) continue;
        await txn.insert(AppDatabase.tableKnowledgeConceptLinks, {
          'user_id': userId,
          'library_id': libraryId,
          'from_concept_id': fromId,
          'to_concept_id': toId,
          'relation_label': relation,
          'created_at': now,
        });
      }
    });
  }

  Future<List<KnowledgeConceptWithDocument>> fetchWeakConcepts({
    required int userId,
    int? libraryId,
    int limit = 20,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    final libraryClause = _appendLibraryClause(
      libraryId,
      args,
      tableAlias: 'concepts',
    );
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT concepts.*,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tableKnowledgeConcepts} concepts
      LEFT JOIN ${AppDatabase.tableSourceDocuments} documents
        ON documents.id = concepts.document_id
      WHERE concepts.user_id = ?
        $libraryClause
      ORDER BY concepts.weakness_score DESC,
               concepts.updated_at DESC,
               concepts.id DESC
      LIMIT ?
      ''', args);

    return rows
        .map(
          (row) => KnowledgeConceptWithDocument(
            concept: KnowledgeConceptRecord.fromMap(row),
            documentTitle:
                (row['document_title'] as String?)?.trim().isNotEmpty == true
                ? (row['document_title'] as String).trim()
                : '未命名资料',
          ),
        )
        .toList(growable: false);
  }

  Future<List<KnowledgeConceptLinkRecord>> fetchLinksByLibrary({
    required int userId,
    int? libraryId,
    int limit = 100,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    final libraryClause = _appendLibraryClause(libraryId, args);
    args.add(limit);
    final rows = await db.rawQuery('''
      SELECT *
      FROM ${AppDatabase.tableKnowledgeConceptLinks}
      WHERE user_id = ?
        $libraryClause
      ORDER BY id DESC
      LIMIT ?
      ''', args);
    return rows.map(KnowledgeConceptLinkRecord.fromMap).toList(growable: false);
  }

  Future<List<KnowledgeNextBestAction>> fetchNextBestActions({
    required int userId,
    int? libraryId,
    int limit = 3,
  }) async {
    final weakConcepts = await fetchWeakConcepts(
      userId: userId,
      libraryId: libraryId,
      limit: limit * 3,
    );
    if (weakConcepts.isEmpty) {
      return const <KnowledgeNextBestAction>[];
    }

    return weakConcepts
        .take(limit)
        .map((item) {
          final concept = item.concept;
          final priority = (100 - concept.masteryScore) + concept.weaknessScore;
          final label = concept.weaknessScore >= 70
              ? '开始 5 分钟专项训练'
              : concept.masteryScore < 50
              ? '先补前置知识'
              : '做 3 道巩固题';
          final reason = concept.weaknessScore >= 70
              ? '薄弱风险较高，建议优先修复。'
              : concept.masteryScore < 50
              ? '掌握度偏低，先补概念再刷题。'
              : '接近掌握，适合用少量题目巩固。';
          return KnowledgeNextBestAction(
            concept: concept,
            documentTitle: item.documentTitle,
            actionLabel: label,
            reason: reason,
            priorityScore: priority,
          );
        })
        .toList(growable: false);
  }

  Future<void> updateMasteryFromPracticeQuestion({
    required int questionId,
    required bool isCorrect,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final questionRows = await db.rawQuery(
      '''
      SELECT questions.*,
             documents.user_id AS user_id,
             documents.library_id AS library_id
      FROM ${AppDatabase.tablePracticeQuestions} questions
      JOIN ${AppDatabase.tableSourceDocuments} documents
        ON documents.id = questions.document_id
      WHERE questions.id = ?
      LIMIT 1
      ''',
      [questionId],
    );
    if (questionRows.isEmpty) {
      return;
    }

    final row = questionRows.first;
    final question = PracticeQuestionRecord.fromMap(row);
    final userId = row['user_id'] as int;
    final concepts = await _relatedConceptsForQuestion(
      userId: userId,
      documentId: question.documentId,
      text: [
        question.questionText,
        question.answerText ?? '',
        question.analysisText ?? '',
      ].join('\n'),
    );
    if (concepts.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final masteryDelta = isCorrect ? 15 : -18;
    final weaknessDelta = isCorrect ? -12 : 22;

    await db.transaction((txn) async {
      for (final concept in concepts.take(4)) {
        await txn.update(
          AppDatabase.tableKnowledgeConcepts,
          {
            'mastery_score': _clampScore(concept.masteryScore + masteryDelta),
            'weakness_score': _clampScore(
              concept.weaknessScore + weaknessDelta,
            ),
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [concept.id],
        );
      }

      if (!isCorrect) {
        final ids = concepts.take(4).map((item) => item.id).toList();
        if (ids.isEmpty) return;
        final placeholders = List.filled(ids.length, '?').join(',');
        final prereqRows = await txn.rawQuery(
          '''
          SELECT DISTINCT prereq.*
          FROM ${AppDatabase.tableKnowledgeConceptLinks} links
          JOIN ${AppDatabase.tableKnowledgeConcepts} prereq
            ON prereq.id = links.from_concept_id
          WHERE links.to_concept_id IN ($placeholders)
            AND links.user_id = ?
            AND (
              links.relation_label LIKE '%前置%' OR
              links.relation_label LIKE '%依赖%' OR
              links.relation_label LIKE '%prerequisite%'
            )
          LIMIT 6
          ''',
          [...ids, userId],
        );
        for (final prereq in prereqRows.map(KnowledgeConceptRecord.fromMap)) {
          await txn.update(
            AppDatabase.tableKnowledgeConcepts,
            {
              'weakness_score': _clampScore(prereq.weaknessScore + 10),
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [prereq.id],
          );
        }
      }
    });
  }

  Future<List<KnowledgeConceptRecord>> _relatedConceptsForQuestion({
    required int userId,
    required int documentId,
    required String text,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableKnowledgeConcepts,
      where:
          'user_id = ? AND id IN (SELECT concept_id FROM concept_documents WHERE document_id = ?)',
      whereArgs: [userId, documentId],
      orderBy: 'weakness_score DESC, updated_at DESC',
      limit: 80,
    );
    final concepts = rows.map(KnowledgeConceptRecord.fromMap).toList();
    if (concepts.isEmpty) {
      return const <KnowledgeConceptRecord>[];
    }

    final lowerText = text.toLowerCase();
    final scored =
        concepts
            .map(
              (concept) => (_conceptQuestionScore(concept, lowerText), concept),
            )
            .where((item) => item.$1 > 0)
            .toList(growable: false)
          ..sort((a, b) => b.$1.compareTo(a.$1));
    if (scored.isNotEmpty) {
      return scored.map((item) => item.$2).toList(growable: false);
    }

    return const [];
  }

  int _conceptQuestionScore(KnowledgeConceptRecord concept, String lowerText) {
    var score = 0;
    final name = concept.name.toLowerCase();
    if (name.isNotEmpty && lowerText.contains(name)) {
      score += 8;
    }
    for (final token in _conceptTokens(concept)) {
      if (lowerText.contains(token)) {
        score += token.length >= 4 ? 3 : 1;
      }
    }
    return score;
  }

  Iterable<String> _conceptTokens(KnowledgeConceptRecord concept) sync* {
    final text = [
      concept.name,
      concept.summary ?? '',
      concept.evidenceText ?? '',
    ].join(' ').toLowerCase();
    final terms = text
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .map((item) => item.trim())
        .where((item) => item.length >= 2)
        .take(12);
    for (final term in terms) {
      yield term;
    }
  }

  int _clampScore(int value) => value.clamp(0, 100).toInt();

  String _appendLibraryClause(
    int? libraryId,
    List<Object?> args, {
    String? tableAlias,
  }) {
    if (libraryId == null) {
      return '';
    }
    args.add(libraryId);
    if (tableAlias == null) args.add(libraryId);
    final prefix = tableAlias == null ? '' : '$tableAlias.';
    return tableAlias == null
        ? 'AND (from_concept_id IN (SELECT cd.concept_id FROM concept_documents cd JOIN document_library_links dl ON dl.document_id = cd.document_id WHERE dl.library_id = ?) OR to_concept_id IN (SELECT cd.concept_id FROM concept_documents cd JOIN document_library_links dl ON dl.document_id = cd.document_id WHERE dl.library_id = ?))'
        : 'AND ${prefix}id IN (SELECT cd.concept_id FROM concept_documents cd JOIN document_library_links dl ON dl.document_id = cd.document_id WHERE dl.library_id = ?)';
  }
}
