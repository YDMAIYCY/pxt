import 'package:sqflite/sqflite.dart';

import '../graph/graph_vocabulary.dart';
import 'app_database.dart';
import 'models/graph_records.dart';

// ========== 跨知识库知识图谱仓库 ==========
// 输入一组 knowledgeBaseId，输出规范化实体、语义关系与来源映射。
// 所有写入都做端点校验、去重与来源记录；删除只失效来源，不误删其他库的数据。

/// 抽取得到的实体草稿。
class GraphNodeDraft {
  const GraphNodeDraft({
    required this.name,
    required this.entityType,
    this.description,
    this.aliases = const <String>[],
    this.evidenceText,
    this.confidence = 0.7,
  });

  final String name;
  final String entityType;
  final String? description;
  final List<String> aliases;
  final String? evidenceText;
  final double confidence;
}

/// 抽取得到的关系草稿，端点用名称表示，落库时解析为实体 ID。
class GraphEdgeDraft {
  const GraphEdgeDraft({
    required this.fromName,
    required this.toName,
    required this.relationType,
    this.description,
    this.confidence = 0.6,
    this.evidenceText,
  });

  final String fromName;
  final String toName;
  final String relationType;
  final String? description;
  final double confidence;
  final String? evidenceText;
}

class GraphExtractionDraft {
  const GraphExtractionDraft({required this.nodes, required this.edges});

  final List<GraphNodeDraft> nodes;
  final List<GraphEdgeDraft> edges;
}

class GraphWriteSummary {
  const GraphWriteSummary({
    required this.createdNodeCount,
    required this.reusedNodeCount,
    required this.createdEdgeCount,
    required this.reusedEdgeCount,
    required this.skippedEdges,
  });

  final int createdNodeCount;
  final int reusedNodeCount;
  final int createdEdgeCount;
  final int reusedEdgeCount;
  final List<String> skippedEdges;

  int get nodeCount => createdNodeCount + reusedNodeCount;
}

/// 某本知识库的图谱覆盖情况。
class GraphLibraryCoverage {
  const GraphLibraryCoverage({
    required this.libraryId,
    required this.documentCount,
    required this.coveredDocumentCount,
    required this.nodeCount,
  });

  final int libraryId;
  final int documentCount;
  final int coveredDocumentCount;
  final int nodeCount;

  bool get isBuilt => coveredDocumentCount > 0;

  bool get isPartial =>
      coveredDocumentCount > 0 && coveredDocumentCount < documentCount;
}

class GraphRepository {
  GraphRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// 单次查询最多返回的节点数，避免大图谱无控制渲染。
  static const int maxVisibleNodes = 600;

  /// SQLite 变量上限保护：IN 子句分批大小。
  static const int _inChunkSize = 400;

  // ================= 查询 =================

  /// 按选中的知识库集合查询可见子图。
  /// 同一实体出现在多本知识库时只返回一个节点，并保留全部来源库。
  Future<GraphViewData> fetchVisibleGraph({
    required int userId,
    required List<int> libraryIds,
    int nodeLimit = maxVisibleNodes,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final normalizedLibraryIds = libraryIds.toSet().toList(growable: false);
    if (normalizedLibraryIds.isEmpty) {
      return const GraphViewData.empty();
    }

    final nodeRows = await db.rawQuery('''
      SELECT nodes.*
      FROM ${AppDatabase.tableGraphNodes} nodes
      WHERE nodes.user_id = ?
        AND nodes.status != ?
        AND nodes.merged_into_node_id IS NULL
        AND EXISTS (
          SELECT 1
          FROM ${AppDatabase.tableGraphNodeSources} sources
          WHERE sources.knowledge_base_id IN (${_placeholders(normalizedLibraryIds.length)})
            AND (
              sources.node_id = nodes.id
              OR sources.node_id IN (
                SELECT merged.id FROM ${AppDatabase.tableGraphNodes} merged
                WHERE merged.merged_into_node_id = nodes.id
              )
            )
        )
      ORDER BY nodes.updated_at DESC, nodes.id DESC
      LIMIT ?
      ''', [
      userId,
      GraphNodeStatus.archived,
      ...normalizedLibraryIds,
      nodeLimit,
    ]);

    if (nodeRows.isEmpty) {
      return GraphViewData(
        nodes: const <GraphViewNode>[],
        edges: const <GraphViewEdge>[],
        libraryIds: normalizedLibraryIds,
        totalNodeCount: 0,
      );
    }

    final nodeIds = nodeRows
        .map((row) => row['id'])
        .whereType<int>()
        .toList(growable: false);
    final librariesByNode = await _librariesForNodes(
      db,
      userId: userId,
      nodeIds: nodeIds,
      scopeLibraryIds: normalizedLibraryIds,
    );

    final edgeRows = await _edgesAmong(
      db,
      userId: userId,
      nodeIds: nodeIds,
    );

    final degree = <int, int>{};
    final edges = <GraphViewEdge>[];
    final visible = nodeIds.toSet();
    for (final row in edgeRows) {
      final edge = GraphEdgeRecord.fromMap(row);
      if (!visible.contains(edge.sourceNodeId) ||
          !visible.contains(edge.targetNodeId)) {
        continue;
      }
      final sourceLibraries =
          librariesByNode[edge.sourceNodeId] ?? const <int>[];
      final targetLibraries =
          librariesByNode[edge.targetNodeId] ?? const <int>[];
      final isCrossLibrary =
          sourceLibraries.isNotEmpty &&
          targetLibraries.isNotEmpty &&
          !sourceLibraries.any(targetLibraries.contains);
      degree[edge.sourceNodeId] = (degree[edge.sourceNodeId] ?? 0) + 1;
      degree[edge.targetNodeId] = (degree[edge.targetNodeId] ?? 0) + 1;
      edges.add(
        GraphViewEdge(
          id: edge.id,
          sourceId: edge.sourceNodeId,
          targetId: edge.targetNodeId,
          relationType: edge.relationType,
          directed: edge.directed,
          confidence: edge.confidence,
          isCrossLibrary: isCrossLibrary,
          description: edge.description,
        ),
      );
    }

    final nodes = nodeRows.map((row) {
      final record = GraphNodeRecord.fromMap(row);
      final libraries = librariesByNode[record.id] ?? const <int>[];
      return GraphViewNode(
        id: record.id,
        label: record.displayName.isEmpty
            ? record.canonicalName
            : record.displayName,
        entityType: record.entityType,
        description: record.description,
        libraryIds: libraries,
        primaryLibraryId: libraries.isEmpty ? null : libraries.first,
        status: record.status,
        degree: degree[record.id] ?? 0,
        aliases: record.aliases,
      );
    }).toList(growable: false);

    return GraphViewData(
      nodes: nodes,
      edges: edges,
      libraryIds: normalizedLibraryIds,
      totalNodeCount: nodes.length,
    );
  }

  /// 在选中范围内按名称/别名/描述搜索实体。
  Future<List<GraphViewNode>> searchNodes({
    required int userId,
    required List<int> libraryIds,
    required String query,
    int limit = 20,
  }) async {
    await _database.ensureSchemaReady();
    final text = GraphNameNormalizer.normalize(query);
    if (text.isEmpty || libraryIds.isEmpty) return const <GraphViewNode>[];

    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT nodes.*
      FROM ${AppDatabase.tableGraphNodes} nodes
      WHERE nodes.user_id = ?
        AND nodes.status != ?
        AND nodes.merged_into_node_id IS NULL
        AND EXISTS (
          SELECT 1
          FROM ${AppDatabase.tableGraphNodeSources} sources
          WHERE sources.knowledge_base_id IN (${_placeholders(libraryIds.length)})
            AND (
              sources.node_id = nodes.id
              OR sources.node_id IN (
                SELECT merged.id FROM ${AppDatabase.tableGraphNodes} merged
                WHERE merged.merged_into_node_id = nodes.id
              )
            )
        )
        AND (
          nodes.canonical_name LIKE ?
          OR nodes.display_name LIKE ?
          OR nodes.aliases_json LIKE ?
          OR COALESCE(nodes.description, '') LIKE ?
          OR EXISTS (
            SELECT 1 FROM ${AppDatabase.tableGraphNodes} merged
            WHERE merged.merged_into_node_id = nodes.id
              AND (merged.canonical_name LIKE ? OR merged.aliases_json LIKE ?)
          )
        )
      ORDER BY nodes.updated_at DESC, nodes.id DESC
      LIMIT ?
      ''', [
      userId,
      GraphNodeStatus.archived,
      ...libraryIds,
      '%$text%',
      '%$query%',
      '%$query%',
      '%$query%',
      '%$text%',
      '%$query%',
      limit,
    ]);

    if (rows.isEmpty) return const <GraphViewNode>[];

    final nodeIds = rows
        .map((row) => row['id'])
        .whereType<int>()
        .toList(growable: false);
    final librariesByNode = await _librariesForNodes(
      db,
      userId: userId,
      nodeIds: nodeIds,
      scopeLibraryIds: libraryIds,
    );

    return rows.map((row) {
      final record = GraphNodeRecord.fromMap(row);
      final libraries = librariesByNode[record.id] ?? const <int>[];
      return GraphViewNode(
        id: record.id,
        label: record.displayName.isEmpty
            ? record.canonicalName
            : record.displayName,
        entityType: record.entityType,
        description: record.description,
        libraryIds: libraries,
        primaryLibraryId: libraries.isEmpty ? null : libraries.first,
        status: record.status,
        degree: 0,
        aliases: record.aliases,
      );
    }).toList(growable: false);
  }

  /// 读取单个实体的完整详情：来源、邻居、所属库名称。
  Future<GraphNodeDetail?> fetchNodeDetail({
    required int userId,
    required int nodeId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;

    final nodeRows = await db.query(
      AppDatabase.tableGraphNodes,
      where: 'id = ? AND user_id = ?',
      whereArgs: [nodeId, userId],
      limit: 1,
    );
    if (nodeRows.isEmpty) return null;
    final node = GraphNodeRecord.fromMap(nodeRows.first);

    final sourceRows = await db.rawQuery('''
      SELECT sources.*,
             COALESCE(libraries.name, '') AS library_name,
             COALESCE(records.title, '') AS record_title,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tableGraphNodeSources} sources
      LEFT JOIN ${AppDatabase.tableKnowledgeLibraries} libraries
        ON libraries.id = sources.knowledge_base_id
      LEFT JOIN import_records records
        ON records.id = sources.import_record_id
      LEFT JOIN ${AppDatabase.tableSourceDocuments} documents
        ON documents.id = sources.source_document_id
      WHERE sources.node_id = ?
         OR sources.node_id IN (
           SELECT merged.id FROM ${AppDatabase.tableGraphNodes} merged
           WHERE merged.merged_into_node_id = ?
         )
      ORDER BY sources.id ASC
      ''', [nodeId, nodeId]);

    final sources = sourceRows
        .map(
          (row) => GraphNodeSourceView(
            source: GraphNodeSourceRecord.fromMap(row),
            libraryName: (row['library_name'] as String?)?.trim() ?? '',
            recordTitle: (row['record_title'] as String?)?.trim() ?? '',
            documentTitle: (row['document_title'] as String?)?.trim() ?? '',
          ),
        )
        .toList(growable: false);

    final libraryNames = <String>[];
    for (final source in sources) {
      final name = source.libraryName;
      if (name.isNotEmpty && !libraryNames.contains(name)) {
        libraryNames.add(name);
      }
    }

    final neighborRows = await db.rawQuery('''
      SELECT edges.*,
             neighbor.*
      FROM ${AppDatabase.tableGraphEdges} edges
      JOIN ${AppDatabase.tableGraphNodes} neighbor
        ON neighbor.id = CASE
             WHEN edges.source_node_id = ? THEN edges.target_node_id
             ELSE edges.source_node_id
           END
      WHERE edges.user_id = ?
        AND edges.review_status != ?
        AND (edges.source_node_id = ? OR edges.target_node_id = ?)
      ORDER BY edges.confidence DESC, edges.id DESC
      LIMIT 120
      ''', [
      nodeId,
      userId,
      GraphEdgeReviewStatus.rejected,
      nodeId,
      nodeId,
    ]);

    final neighbors = neighborRows.map((row) {
      final edge = GraphEdgeRecord.fromMap(row);
      return GraphNodeNeighborView(
        node: GraphNodeRecord.fromMap(row),
        edge: edge,
        isOutgoing: edge.sourceNodeId == nodeId,
      );
    }).toList(growable: false);

    return GraphNodeDetail(
      node: node,
      sources: sources,
      neighbors: neighbors,
      libraryNames: libraryNames,
    );
  }

  /// 每本知识库已建图谱的节点数（被合并的子实体计入父实体）。
  Future<Map<int, int>> nodeCountsByLibrary(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT library_id, COUNT(DISTINCT owner_node_id) AS node_count
      FROM (
        SELECT sources.knowledge_base_id AS library_id,
               sources.node_id AS owner_node_id
        FROM ${AppDatabase.tableGraphNodeSources} sources
        JOIN ${AppDatabase.tableGraphNodes} nodes
          ON nodes.id = sources.node_id AND nodes.status != ?
        WHERE sources.user_id = ?
          AND sources.knowledge_base_id IS NOT NULL
        UNION ALL
        SELECT sources.knowledge_base_id, merged.merged_into_node_id
        FROM ${AppDatabase.tableGraphNodeSources} sources
        JOIN ${AppDatabase.tableGraphNodes} merged ON merged.id = sources.node_id
        WHERE sources.user_id = ?
          AND sources.knowledge_base_id IS NOT NULL
          AND merged.merged_into_node_id IS NOT NULL
      )
      GROUP BY library_id
      ''', [GraphNodeStatus.archived, userId, userId]);
    return {
      for (final row in rows)
        if ((row['library_id'] as num?) != null)
          (row['library_id'] as num).toInt(): _readInt(row['node_count']),
    };
  }

  /// 某本知识库的图谱覆盖情况：多少页资料、其中多少页已进入图谱。
  Future<GraphLibraryCoverage> libraryCoverage({
    required int userId,
    required int libraryId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final documentRows = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ${AppDatabase.tableSourceDocuments}
      WHERE user_id = ? AND library_id = ?
      ''', [userId, libraryId]);
    final coveredRows = await db.rawQuery('''
      SELECT COUNT(DISTINCT source_document_id) AS covered
      FROM ${AppDatabase.tableGraphNodeSources}
      WHERE user_id = ? AND knowledge_base_id = ?
        AND source_document_id IS NOT NULL
      ''', [userId, libraryId]);
    final nodeRows = await db.rawQuery('''
      SELECT COUNT(DISTINCT owner_node_id) AS node_count
      FROM (
        SELECT sources.node_id AS owner_node_id
        FROM ${AppDatabase.tableGraphNodeSources} sources
        JOIN ${AppDatabase.tableGraphNodes} nodes
          ON nodes.id = sources.node_id AND nodes.status != ?
        WHERE sources.user_id = ? AND sources.knowledge_base_id = ?
        UNION ALL
        SELECT merged.merged_into_node_id
        FROM ${AppDatabase.tableGraphNodeSources} sources
        JOIN ${AppDatabase.tableGraphNodes} merged ON merged.id = sources.node_id
        WHERE sources.user_id = ? AND sources.knowledge_base_id = ?
          AND merged.merged_into_node_id IS NOT NULL
      )
      ''', [
      GraphNodeStatus.archived,
      userId,
      libraryId,
      userId,
      libraryId,
    ]);

    return GraphLibraryCoverage(
      libraryId: libraryId,
      documentCount: _readInt(documentRows.isEmpty
          ? null
          : documentRows.first['total']),
      coveredDocumentCount: _readInt(coveredRows.isEmpty
          ? null
          : coveredRows.first['covered']),
      nodeCount: _readInt(nodeRows.isEmpty
          ? null
          : nodeRows.first['node_count']),
    );
  }

  /// 已进入图谱的源文档 ID 集合（用于判断哪些资料还没建图谱）。
  Future<Set<int>> coveredDocumentIds({
    required int userId,
    required int libraryId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT sources.source_document_id AS document_id
      FROM ${AppDatabase.tableGraphNodeSources} sources
      WHERE sources.user_id = ? AND sources.knowledge_base_id = ?
        AND sources.source_document_id IS NOT NULL
      ''', [userId, libraryId]);
    return rows
        .map((row) => row['document_id'])
        .whereType<int>()
        .toSet();
  }

  /// 可能指向同一概念的候选实体：名称规范化后相同但实体类型不同。
  /// 只作为「待用户确认」的合并建议，绝不自动合并。
  Future<List<GraphNodeRecord>> findMergeCandidates({
    required int userId,
    required int nodeId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableGraphNodes,
      where: 'id = ? AND user_id = ?',
      whereArgs: [nodeId, userId],
      limit: 1,
    );
    if (rows.isEmpty) return const <GraphNodeRecord>[];
    final node = GraphNodeRecord.fromMap(rows.first);

    final candidates = await db.query(
      AppDatabase.tableGraphNodes,
      where:
          'user_id = ? AND id != ? AND status != ? AND merged_into_node_id IS NULL '
          'AND canonical_name = ?',
      whereArgs: [
        userId,
        nodeId,
        GraphNodeStatus.archived,
        node.canonicalName,
      ],
      limit: 8,
    );
    return candidates.map(GraphNodeRecord.fromMap).toList(growable: false);
  }

  // ================= 写入 =================

  /// 将一次抽取结果写入规范图谱层。
  /// 同名同类型的实体自动复用；关系做端点校验与去重。
  /// [replaceDocumentContributions] 为真时，先清掉该文档旧的贡献再写入（重建语义）。
  Future<GraphWriteSummary> persistExtraction({
    required int userId,
    required int? knowledgeBaseId,
    required int? importRecordId,
    required int? sourceDocumentId,
    required GraphExtractionDraft draft,
    String origin = GraphEdgeOrigin.document,
    String? modelVersion,
    bool replaceDocumentContributions = true,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.transaction((txn) async {
      if (replaceDocumentContributions && sourceDocumentId != null) {
        await txn.delete(
          AppDatabase.tableGraphNodeSources,
          where: 'user_id = ? AND source_document_id = ?',
          whereArgs: [userId, sourceDocumentId],
        );
        await txn.delete(
          AppDatabase.tableGraphEdgeEvidence,
          where: 'user_id = ? AND source_document_id = ?',
          whereArgs: [userId, sourceDocumentId],
        );
      }

      var createdNodes = 0;
      var reusedNodes = 0;
      final nodeIdByKey = <String, int>{};
      final nodeIdByName = <String, List<int>>{};
      final entityTypeByKey = <String, String>{};

      for (final nodeDraft in draft.nodes) {
        final name = nodeDraft.name.trim();
        if (name.isEmpty) continue;
        final entityType = GraphEntityTypes.normalize(nodeDraft.entityType);
        final canonicalKey = GraphNameNormalizer.canonicalKey(name, entityType);
        if (canonicalKey.isEmpty) continue;

        var nodeId = nodeIdByKey[canonicalKey];
        if (nodeId == null) {
          final existing = await _findExistingNode(
            txn,
            userId: userId,
            canonicalKey: canonicalKey,
            name: name,
            aliases: nodeDraft.aliases,
          );
          if (existing != null) {
            nodeId = existing.id;
            await _mergeNodeFields(
              txn,
              existing: existing,
              draft: nodeDraft,
              entityType: entityType,
              now: now,
            );
            reusedNodes++;
          } else {
            nodeId = await txn.insert(AppDatabase.tableGraphNodes, {
              'user_id': userId,
              'canonical_key': canonicalKey,
              'canonical_name': GraphNameNormalizer.normalize(name),
              'display_name': name,
              'entity_type': entityType,
              'description': _emptyToNull(nodeDraft.description),
              'aliases_json': encodeStringList(nodeDraft.aliases),
              'status': nodeDraft.confidence >= 0.5
                  ? GraphNodeStatus.active
                  : GraphNodeStatus.pendingReview,
              'merged_into_node_id': null,
              'created_at': now,
              'updated_at': now,
            });
            createdNodes++;
          }
          nodeIdByKey[canonicalKey] = nodeId;
          entityTypeByKey[canonicalKey] = entityType;
        }

        final normalizedName = GraphNameNormalizer.normalize(name);
        final nameBucket = nodeIdByName.putIfAbsent(
          normalizedName,
          () => <int>[],
        );
        if (!nameBucket.contains(nodeId)) nameBucket.add(nodeId);
        for (final alias in nodeDraft.aliases) {
          final aliasKey = GraphNameNormalizer.normalize(alias);
          if (aliasKey.isEmpty) continue;
          final aliasBucket = nodeIdByName.putIfAbsent(
            aliasKey,
            () => <int>[],
          );
          if (!aliasBucket.contains(nodeId)) aliasBucket.add(nodeId);
        }

        await _upsertNodeSource(
          txn,
          userId: userId,
          nodeId: nodeId,
          knowledgeBaseId: knowledgeBaseId,
          importRecordId: importRecordId,
          sourceDocumentId: sourceDocumentId,
          evidenceText: nodeDraft.evidenceText,
          now: now,
        );
      }

      var createdEdges = 0;
      var reusedEdges = 0;
      final skippedEdges = <String>[];

      for (final edgeDraft in draft.edges) {
        final fromKey = GraphNameNormalizer.normalize(edgeDraft.fromName);
        final toKey = GraphNameNormalizer.normalize(edgeDraft.toName);
        if (fromKey.isEmpty || toKey.isEmpty) continue;
        final fromCandidates = await _resolveNameCandidates(
          txn,
          userId: userId,
          nodeIdByName: nodeIdByName,
          normalizedName: fromKey,
        );
        final toCandidates = await _resolveNameCandidates(
          txn,
          userId: userId,
          nodeIdByName: nodeIdByName,
          normalizedName: toKey,
        );
        if (fromCandidates.length != 1 || toCandidates.length != 1) {
          skippedEdges.add(
            '${edgeDraft.fromName} -> ${edgeDraft.toName}: 端点无法唯一确定',
          );
          continue;
        }
        final sourceNodeId = fromCandidates.single;
        final targetNodeId = toCandidates.single;
        if (sourceNodeId == targetNodeId) continue;

        final relationSpec = GraphRelationTypes.specFor(edgeDraft.relationType);
        final orderedSource = relationSpec.directed
            ? sourceNodeId
            : (sourceNodeId < targetNodeId ? sourceNodeId : targetNodeId);
        final orderedTarget = relationSpec.directed
            ? targetNodeId
            : (sourceNodeId < targetNodeId ? targetNodeId : sourceNodeId);

        final existingEdgeRows = await txn.query(
          AppDatabase.tableGraphEdges,
          columns: ['id'],
          where:
              'user_id = ? AND source_node_id = ? AND target_node_id = ? AND relation_type = ?',
          whereArgs: [
            userId,
            orderedSource,
            orderedTarget,
            relationSpec.type,
          ],
          limit: 1,
        );

        int edgeId;
        if (existingEdgeRows.isEmpty) {
          edgeId = await txn.insert(AppDatabase.tableGraphEdges, {
            'user_id': userId,
            'source_node_id': orderedSource,
            'target_node_id': orderedTarget,
            'relation_type': relationSpec.type,
            'directed': relationSpec.directed ? 1 : 0,
            'description': _emptyToNull(edgeDraft.description),
            'confidence': edgeDraft.confidence.clamp(0.0, 1.0),
            'review_status': GraphEdgeReviewStatus.auto,
            'origin': origin,
            'created_at': now,
            'updated_at': now,
          });
          createdEdges++;
        } else {
          edgeId = existingEdgeRows.first['id'] as int;
          await txn.update(
            AppDatabase.tableGraphEdges,
            {
              'description': ?_emptyToNull(edgeDraft.description),
              'confidence': edgeDraft.confidence.clamp(0.0, 1.0),
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [edgeId],
          );
          reusedEdges++;
        }

        await _upsertEdgeEvidence(
          txn,
          userId: userId,
          edgeId: edgeId,
          knowledgeBaseId: knowledgeBaseId,
          importRecordId: importRecordId,
          sourceDocumentId: sourceDocumentId,
          evidenceText: edgeDraft.evidenceText,
          confidence: edgeDraft.confidence,
          now: now,
        );
      }

      await _pruneWithin(txn, userId: userId, now: now);

      return GraphWriteSummary(
        createdNodeCount: createdNodes,
        reusedNodeCount: reusedNodes,
        createdEdgeCount: createdEdges,
        reusedEdgeCount: reusedEdges,
        skippedEdges: skippedEdges,
      );
    });
  }

  /// 用户确认一条自动关系。
  Future<void> confirmEdge({required int userId, required int edgeId}) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await db.update(
      AppDatabase.tableGraphEdges,
      {
        'review_status': GraphEdgeReviewStatus.confirmed,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [edgeId, userId],
    );
  }

  /// 用户否决一条自动关系（保留记录但不再展示）。
  Future<void> rejectEdge({required int userId, required int edgeId}) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await db.update(
      AppDatabase.tableGraphEdges,
      {
        'review_status': GraphEdgeReviewStatus.rejected,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [edgeId, userId],
    );
  }

  /// 人工把 [sourceNodeId] 合并进 [targetNodeId]（低置信度合并的用户确认）。
  ///
  /// 设计取舍：实体来源（graph_node_sources）**原地保留**在源实体上，只在节点上
  /// 标记 `merged_into_node_id`；查询时把子实体的来源并入父实体。这样撤销合并
  /// 是无损的。关系边会被搬到父实体并去重（关系不是来源，撤销合并不会重建它们，
  /// 需要时重新生成图谱即可）。
  Future<void> mergeNodes({
    required int userId,
    required int sourceNodeId,
    required int targetNodeId,
  }) async {
    if (sourceNodeId == targetNodeId) return;
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final rows = await txn.query(
        AppDatabase.tableGraphNodes,
        columns: ['id', 'merged_into_node_id'],
        where: 'id IN (?, ?) AND user_id = ?',
        whereArgs: [sourceNodeId, targetNodeId, userId],
      );
      if (rows.length != 2) return;
      // 不允许把已被合并的实体当作合并目标，避免出现合并链。
      final target = rows.firstWhere((row) => row['id'] == targetNodeId);
      if (target['merged_into_node_id'] != null) return;

      // 关系：重算端点，遇到重复关系则把证据并入已有边。
      final edges = await txn.query(
        AppDatabase.tableGraphEdges,
        where: 'user_id = ? AND (source_node_id = ? OR target_node_id = ?)',
        whereArgs: [userId, sourceNodeId, sourceNodeId],
      );
      for (final edge in edges) {
        final edgeId = edge['id'] as int;
        final newSource = edge['source_node_id'] == sourceNodeId
            ? targetNodeId
            : edge['source_node_id'] as int;
        final newTarget = edge['target_node_id'] == sourceNodeId
            ? targetNodeId
            : edge['target_node_id'] as int;
        if (newSource == newTarget) {
          await txn.delete(
            AppDatabase.tableGraphEdges,
            where: 'id = ?',
            whereArgs: [edgeId],
          );
          continue;
        }
        final duplicate = await txn.query(
          AppDatabase.tableGraphEdges,
          columns: ['id'],
          where:
              'user_id = ? AND source_node_id = ? AND target_node_id = ? '
              'AND relation_type = ? AND id != ?',
          whereArgs: [
            userId,
            newSource,
            newTarget,
            edge['relation_type'],
            edgeId,
          ],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          await txn.update(
            AppDatabase.tableGraphEdgeEvidence,
            {'edge_id': duplicate.first['id']},
            where: 'edge_id = ?',
            whereArgs: [edgeId],
          );
          await txn.delete(
            AppDatabase.tableGraphEdges,
            where: 'id = ?',
            whereArgs: [edgeId],
          );
        } else {
          await txn.update(
            AppDatabase.tableGraphEdges,
            {
              'source_node_id': newSource,
              'target_node_id': newTarget,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [edgeId],
          );
        }
      }

      await txn.update(
        AppDatabase.tableGraphNodes,
        {
          'status': GraphNodeStatus.archived,
          'merged_into_node_id': targetNodeId,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [sourceNodeId],
      );
    });
  }

  /// 撤销一次合并。
  Future<void> unmergeNode({
    required int userId,
    required int nodeId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await db.update(
      AppDatabase.tableGraphNodes,
      {
        'status': GraphNodeStatus.active,
        'merged_into_node_id': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND user_id = ? AND merged_into_node_id IS NOT NULL',
      whereArgs: [nodeId, userId],
    );
  }

  /// 清理孤立实体与失效关系（只归档，不物理删除有历史的实体）。
  Future<int> pruneOrphans(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.transaction((txn) => _pruneWithin(txn, userId: userId, now: now));
  }

  // ================= 构建任务 =================

  Future<int> createBuildJob({
    required int userId,
    required String scope,
    int? scopeId,
    int totalUnits = 0,
    String? sourceVersion,
    String? modelVersion,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert(AppDatabase.tableGraphBuildJobs, {
      'user_id': userId,
      'scope': scope,
      'scope_id': scopeId,
      'status': GraphBuildStatus.running,
      'progress': 0,
      'total_units': totalUnits,
      'done_units': 0,
      'source_version': sourceVersion,
      'model_version': modelVersion,
      'error_message': null,
      'created_at': now,
      'updated_at': now,
      'completed_at': null,
    });
  }

  Future<void> updateBuildJob({
    required int jobId,
    int? doneUnits,
    int? totalUnits,
    String? status,
    String? errorMessage,
    bool complete = false,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final done = doneUnits;
    final total = totalUnits;
    final progress = (done != null && total != null && total > 0)
        ? ((done / total) * 100).round().clamp(0, 100)
        : null;
    await db.update(
      AppDatabase.tableGraphBuildJobs,
      {
        'done_units': ?done,
        'total_units': ?total,
        'progress': ?progress,
        'status': ?status,
        'error_message': errorMessage,
        'updated_at': now,
        if (complete) 'completed_at': now,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  Future<GraphBuildJobRecord?> latestBuildJob({
    required int userId,
    String? scope,
    int? scopeId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    var clause = '';
    if (scope != null) {
      clause += ' AND scope = ?';
      args.add(scope);
    }
    if (scopeId != null) {
      clause += ' AND scope_id = ?';
      args.add(scopeId);
    }
    final rows = await db.rawQuery('''
      SELECT *
      FROM ${AppDatabase.tableGraphBuildJobs}
      WHERE user_id = ? $clause
      ORDER BY id DESC
      LIMIT 1
      ''', args);
    if (rows.isEmpty) return null;
    return GraphBuildJobRecord.fromMap(rows.first);
  }

  Future<List<GraphBuildJobRecord>> recentBuildJobs({
    required int userId,
    int limit = 10,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableGraphBuildJobs,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(GraphBuildJobRecord.fromMap).toList(growable: false);
  }

  Future<void> markRunningJobsCancelled(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      AppDatabase.tableGraphBuildJobs,
      {
        'status': GraphBuildStatus.cancelled,
        'updated_at': now,
        'completed_at': now,
      },
      where: 'user_id = ? AND status IN (?, ?)',
      whereArgs: [userId, GraphBuildStatus.pending, GraphBuildStatus.running],
    );
  }

  // ================= 视图偏好 =================

  /// 保存用户上次选择的知识库集合。这是视图筛选状态，不是知识实体。
  Future<void> saveSelectedLibraries({
    required int userId,
    required List<int> libraryIds,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      AppDatabase.tableGraphViewPrefs,
      {
        'user_id': userId,
        'selected_library_ids_json': encodeIntList(libraryIds),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<int>> loadSelectedLibraries(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableGraphViewPrefs,
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return const <int>[];
    return decodeIntList(rows.first['selected_library_ids_json']);
  }

  // ================= 内部辅助 =================

  Future<Map<int, List<int>>> _librariesForNodes(
    DatabaseExecutor db, {
    required int userId,
    required List<int> nodeIds,
    required List<int> scopeLibraryIds,
  }) async {
    final result = <int, List<int>>{};
    final scope = scopeLibraryIds.toSet();

    void add(int? nodeId, int? libraryId) {
      if (nodeId == null || libraryId == null) return;
      if (scope.isNotEmpty && !scope.contains(libraryId)) return;
      final bucket = result.putIfAbsent(nodeId, () => <int>[]);
      if (!bucket.contains(libraryId)) bucket.add(libraryId);
    }

    for (final chunk in _chunks(nodeIds, _inChunkSize)) {
      final placeholders = _placeholders(chunk.length);
      // 实体自身的来源，以及被合并进来的子实体的来源都归属到父实体。
      final rows = await db.rawQuery('''
        SELECT sources.node_id AS owner_node_id, sources.knowledge_base_id
        FROM ${AppDatabase.tableGraphNodeSources} sources
        WHERE sources.user_id = ?
          AND sources.knowledge_base_id IS NOT NULL
          AND sources.node_id IN ($placeholders)
        UNION ALL
        SELECT merged.merged_into_node_id AS owner_node_id,
               sources.knowledge_base_id
        FROM ${AppDatabase.tableGraphNodeSources} sources
        JOIN ${AppDatabase.tableGraphNodes} merged ON merged.id = sources.node_id
        WHERE sources.user_id = ?
          AND sources.knowledge_base_id IS NOT NULL
          AND merged.merged_into_node_id IN ($placeholders)
        ''', [userId, ...chunk, userId, ...chunk]);
      for (final row in rows) {
        add(
          (row['owner_node_id'] as num?)?.toInt(),
          (row['knowledge_base_id'] as num?)?.toInt(),
        );
      }
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _edgesAmong(
    DatabaseExecutor db, {
    required int userId,
    required List<int> nodeIds,
  }) async {
    final result = <Map<String, Object?>>[];
    final seen = <int>{};
    for (final chunk in _chunks(nodeIds, _inChunkSize)) {
      final placeholders = _placeholders(chunk.length);
      final rows = await db.rawQuery('''
        SELECT *
        FROM ${AppDatabase.tableGraphEdges}
        WHERE user_id = ?
          AND review_status != ?
          AND source_node_id IN ($placeholders)
          AND target_node_id IN ($placeholders)
        ''', [
        userId,
        GraphEdgeReviewStatus.rejected,
        ...chunk,
        ...chunk,
      ]);
      for (final row in rows) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null || !seen.add(id)) continue;
        result.add(row);
      }
    }
    return result;
  }

  Future<GraphNodeRecord?> _findExistingNode(
    DatabaseExecutor txn, {
    required int userId,
    required String canonicalKey,
    required String name,
    required List<String> aliases,
  }) async {
    final byKey = await txn.query(
      AppDatabase.tableGraphNodes,
      where: 'user_id = ? AND canonical_key = ? AND merged_into_node_id IS NULL',
      whereArgs: [userId, canonicalKey],
      limit: 1,
    );
    if (byKey.isNotEmpty) return GraphNodeRecord.fromMap(byKey.first);

    // 别名精确匹配，且要求实体类型一致；不做模糊字符串合并。
    final entityType = canonicalKey.split('|').last;
    final candidateKeys = <String>{
      GraphNameNormalizer.normalize(name),
      ...aliases.map(GraphNameNormalizer.normalize),
    }..removeWhere((key) => key.isEmpty);
    if (candidateKeys.isEmpty) return null;

    for (final key in candidateKeys) {
      final rows = await txn.query(
        AppDatabase.tableGraphNodes,
        where:
            'user_id = ? AND entity_type = ? AND merged_into_node_id IS NULL '
            'AND (canonical_name = ? OR aliases_json LIKE ?)',
        whereArgs: [userId, entityType, key, '%$key%'],
      );
      for (final row in rows) {
        final record = GraphNodeRecord.fromMap(row);
        final recordAliases = record.aliases
            .map(GraphNameNormalizer.normalize)
            .toSet();
        if (record.canonicalName == key || recordAliases.contains(key)) {
          return record;
        }
      }
    }
    return null;
  }

  Future<void> _mergeNodeFields(
    DatabaseExecutor txn, {
    required GraphNodeRecord existing,
    required GraphNodeDraft draft,
    required String entityType,
    required String now,
  }) async {
    final mergedAliases = <String>{...existing.aliases};
    for (final alias in draft.aliases) {
      final trimmed = alias.trim();
      if (trimmed.isNotEmpty) mergedAliases.add(trimmed);
    }
    if (existing.displayName.trim() != draft.name.trim()) {
      mergedAliases.add(existing.displayName);
    }

    await txn.update(
      AppDatabase.tableGraphNodes,
      {
        'entity_type': entityType,
        'description': existing.description ??
            _emptyToNull(draft.description),
        'aliases_json': encodeStringList(mergedAliases.toList()),
        'status': existing.status == GraphNodeStatus.archived
            ? GraphNodeStatus.active
            : existing.status,
        'merged_into_node_id': null,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [existing.id],
    );
  }

  /// 解析关系端点到实体 ID：先看本次草稿，再回退到已持久化的实体。
  /// 跨库关系发现不携带节点草稿，必须走这条回退路径。
  Future<List<int>> _resolveNameCandidates(
    DatabaseExecutor txn, {
    required int userId,
    required Map<String, List<int>> nodeIdByName,
    required String normalizedName,
  }) async {
    if (normalizedName.isEmpty) return const <int>[];
    final cached = nodeIdByName[normalizedName];
    if (cached != null) return cached;

    final rows = await txn.query(
      AppDatabase.tableGraphNodes,
      where:
          'user_id = ? AND status != ? AND merged_into_node_id IS NULL '
          'AND (canonical_name = ? OR aliases_json LIKE ?)',
      whereArgs: [
        userId,
        GraphNodeStatus.archived,
        normalizedName,
        '%$normalizedName%',
      ],
    );
    final ids = <int>[];
    for (final row in rows) {
      final record = GraphNodeRecord.fromMap(row);
      final aliases = record.aliases
          .map(GraphNameNormalizer.normalize)
          .toSet();
      if (record.canonicalName == normalizedName ||
          aliases.contains(normalizedName)) {
        ids.add(record.id);
      }
    }
    nodeIdByName[normalizedName] = ids;
    return ids;
  }

  Future<void> _upsertNodeSource(
    DatabaseExecutor txn, {
    required int userId,
    required int nodeId,
    required int? knowledgeBaseId,
    required int? importRecordId,
    required int? sourceDocumentId,
    required String? evidenceText,
    required String now,
  }) async {
    final existing = await txn.query(
      AppDatabase.tableGraphNodeSources,
      columns: ['id'],
      where:
          'node_id = ? AND user_id = ? AND IFNULL(knowledge_base_id, -1) = ? '
          'AND IFNULL(import_record_id, -1) = ? AND IFNULL(source_document_id, -1) = ?',
      whereArgs: [
        nodeId,
        userId,
        knowledgeBaseId ?? -1,
        importRecordId ?? -1,
        sourceDocumentId ?? -1,
      ],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final values = <String, Object?>{
        'evidence_text': ?_emptyToNull(evidenceText),
      };
      if (values.isNotEmpty) {
        await txn.update(
          AppDatabase.tableGraphNodeSources,
          values,
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      }
      return;
    }
    await txn.insert(AppDatabase.tableGraphNodeSources, {
      'node_id': nodeId,
      'user_id': userId,
      'knowledge_base_id': knowledgeBaseId,
      'import_record_id': importRecordId,
      'source_document_id': sourceDocumentId,
      'source_page_id': sourceDocumentId,
      'source_text_range': null,
      'evidence_text': _emptyToNull(evidenceText),
      'created_at': now,
    });
  }

  Future<void> _upsertEdgeEvidence(
    DatabaseExecutor txn, {
    required int userId,
    required int edgeId,
    required int? knowledgeBaseId,
    required int? importRecordId,
    required int? sourceDocumentId,
    required String? evidenceText,
    required double confidence,
    required String now,
  }) async {
    final existing = await txn.query(
      AppDatabase.tableGraphEdgeEvidence,
      columns: ['id'],
      where:
          'edge_id = ? AND user_id = ? AND IFNULL(knowledge_base_id, -1) = ? '
          'AND IFNULL(import_record_id, -1) = ? AND IFNULL(source_document_id, -1) = ?',
      whereArgs: [
        edgeId,
        userId,
        knowledgeBaseId ?? -1,
        importRecordId ?? -1,
        sourceDocumentId ?? -1,
      ],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await txn.update(
        AppDatabase.tableGraphEdgeEvidence,
        {
          'evidence_text': ?_emptyToNull(evidenceText),
          'confidence': confidence.clamp(0.0, 1.0),
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      return;
    }    await txn.insert(AppDatabase.tableGraphEdgeEvidence, {
      'edge_id': edgeId,
      'user_id': userId,
      'knowledge_base_id': knowledgeBaseId,
      'import_record_id': importRecordId,
      'source_document_id': sourceDocumentId,
      'source_page_id': sourceDocumentId,
      'evidence_text': _emptyToNull(evidenceText),
      'confidence': confidence.clamp(0.0, 1.0),
      'created_at': now,
    });
  }

  Future<int> _pruneWithin(
    DatabaseExecutor txn, {
    required int userId,
    required String now,
  }) async {
    // 关系先于节点清理：无证据的自动关系直接删除。
    await txn.delete(
      AppDatabase.tableGraphEdges,
      where:
          'user_id = ? AND review_status = ? AND NOT EXISTS ('
          'SELECT 1 FROM ${AppDatabase.tableGraphEdgeEvidence} evidence '
          'WHERE evidence.edge_id = ${AppDatabase.tableGraphEdges}.id)',
      whereArgs: [userId, GraphEdgeReviewStatus.auto],
    );

    // 无来源的实体归档，而不是物理删除（保留历史与人工审核状态）。
    final archived = await txn.rawUpdate('''
      UPDATE ${AppDatabase.tableGraphNodes}
      SET status = ?, updated_at = ?
      WHERE user_id = ?
        AND status != ?
        AND merged_into_node_id IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM ${AppDatabase.tableGraphNodeSources} sources
          WHERE sources.node_id = ${AppDatabase.tableGraphNodes}.id
        )
      ''', [GraphNodeStatus.archived, now, userId, GraphNodeStatus.archived]);

    // 归档节点参与的自动关系失效。
    await txn.delete(
      AppDatabase.tableGraphEdges,
      where:
          'user_id = ? AND review_status = ? AND ('
          'source_node_id IN (SELECT id FROM ${AppDatabase.tableGraphNodes} WHERE status = ?) '
          'OR target_node_id IN (SELECT id FROM ${AppDatabase.tableGraphNodes} WHERE status = ?))',
      whereArgs: [
        userId,
        GraphEdgeReviewStatus.auto,
        GraphNodeStatus.archived,
        GraphNodeStatus.archived,
      ],
    );

    return archived;
  }

  String _placeholders(int count) => List.filled(count, '?').join(',');

  Iterable<List<T>> _chunks<T>(List<T> source, int size) sync* {
    for (var start = 0; start < source.length; start += size) {
      final end = start + size < source.length ? start + size : source.length;
      yield source.sublist(start, end);
    }
  }

  static String? _emptyToNull(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// 整数列表的 JSON 编解码（视图偏好使用）。
String encodeIntList(List<int> values) {
  final unique = <int>[];
  for (final value in values) {
    if (!unique.contains(value)) unique.add(value);
  }
  return '[${unique.join(',')}]';
}

List<int> decodeIntList(Object? value) {
  final text = (value as String?)?.trim() ?? '';
  if (text.isEmpty) return const <int>[];
  final trimmed = text.startsWith('[') && text.endsWith(']')
      ? text.substring(1, text.length - 1)
      : text;
  if (trimmed.trim().isEmpty) return const <int>[];
  return trimmed
      .split(',')
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .toList(growable: false);
}
