import 'app_database.dart';
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
      final oldConceptRows = await txn.query(
        AppDatabase.tableKnowledgeConcepts,
        columns: ['id'],
        where: 'document_id = ? AND user_id = ?',
        whereArgs: [documentId, userId],
      );
      final oldConceptIds = oldConceptRows
          .map((row) => row['id'])
          .whereType<int>()
          .toList(growable: false);
      if (oldConceptIds.isNotEmpty) {
        final placeholders = List.filled(oldConceptIds.length, '?').join(',');
        await txn.delete(
          AppDatabase.tableKnowledgeConceptLinks,
          where:
              'from_concept_id IN ($placeholders) OR to_concept_id IN ($placeholders)',
          whereArgs: [...oldConceptIds, ...oldConceptIds],
        );
      }
      await txn.delete(
        AppDatabase.tableKnowledgeConcepts,
        where: 'document_id = ? AND user_id = ?',
        whereArgs: [documentId, userId],
      );

      final conceptIdsByName = <String, int>{};
      for (final concept in draft.concepts) {
        final name = concept.name.trim();
        if (name.isEmpty || conceptIdsByName.containsKey(name)) {
          continue;
        }
        final conceptId = await txn.insert(AppDatabase.tableKnowledgeConcepts, {
          'user_id': userId,
          'library_id': libraryId,
          'document_id': documentId,
          'name': name,
          'summary': concept.summary.trim(),
          'evidence_text': concept.evidenceText.trim(),
          'source_type': sourceType,
          'source_id': null,
          'mastery_score': _clampScore(concept.masteryScore),
          'weakness_score': _clampScore(concept.weaknessScore),
          'created_at': now,
          'updated_at': now,
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
    final libraryClause = _appendLibraryClause(libraryId, args);
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

  int _clampScore(int value) => value.clamp(0, 100).toInt();

  String _appendLibraryClause(int? libraryId, List<Object?> args) {
    if (libraryId == null) {
      return '';
    }
    args.add(libraryId);
    return 'AND concepts.library_id = ?';
  }
}
