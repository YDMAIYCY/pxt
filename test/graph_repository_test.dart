import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/graph_repository.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/models/graph_records.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/source_document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase app;
  late Database db;
  late GraphRepository graph;
  const now = '2026-10-14T01:00:00.000Z';

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    graph = GraphRepository(database: app);
    for (final id in [1, 2]) {
      await db.insert('users', {
        'id': id,
        'username': 'u$id',
        'password_hash': 'x',
        'password_salt': 'x',
        'created_at': now,
        'updated_at': now,
      });
      for (final libraryId in [1, 2]) {
        await db.insert('knowledge_libraries', {
          'id': id * 10 + libraryId,
          'user_id': id,
          'name': '库${id}_$libraryId',
          'created_at': now,
          'updated_at': now,
        });
      }
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<({int documentId, int? importRecordId})> addSource({
    int user = 1,
    int library = 11,
    String title = '资料',
  }) async {
    final document = await SourceDocumentRepository(
      database: app,
    ).createSourceDocument(
      userId: user,
      libraryId: library,
      sourceType: 'camera_capture',
      imagePath: '/fixture/$title.png',
      title: title,
    );
    final rows = await db.query(
      'source_documents',
      columns: ['import_record_id'],
      where: 'id = ?',
      whereArgs: [document.id],
      limit: 1,
    );
    return (
      documentId: document.id,
      importRecordId: rows.first['import_record_id'] as int?,
    );
  }

  Future<GraphWriteSummary> write({
    required int user,
    required int? library,
    required int? document,
    int? record,
    required GraphExtractionDraft draft,
    String origin = GraphEdgeOrigin.document,
    bool replace = true,
  }) => graph.persistExtraction(
    userId: user,
    knowledgeBaseId: library,
    importRecordId: record,
    sourceDocumentId: document,
    draft: draft,
    origin: origin,
    replaceDocumentContributions: replace,
  );

  const calculusDraft = GraphExtractionDraft(
    nodes: [
      GraphNodeDraft(
        name: '导数',
        entityType: '概念',
        description: '函数在一点的变化率',
        evidenceText: '导数定义为极限',
      ),
      GraphNodeDraft(
        name: '梯度',
        entityType: '概念',
        aliases: ['gradient', '梯度向量'],
        description: '多元函数的最速上升方向',
      ),
      GraphNodeDraft(
        name: '偏导数',
        entityType: '概念',
      ),
    ],
    edges: [
      GraphEdgeDraft(fromName: '偏导数', toName: '导数', relationType: '前置知识'),
      GraphEdgeDraft(fromName: '梯度', toName: '偏导数', relationType: '依赖于'),
      GraphEdgeDraft(fromName: '梯度', toName: '导数', relationType: '相关'),
    ],
  );

  group('schema', () {
    test('当前 schema 建立规范图谱表与索引', () async {
      // v18 引入规范图谱表；后续版本只做增量升级。
      expect(AppDatabase.databaseVersion, greaterThanOrEqualTo(18));
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables.map((row) => row['name']).toSet();
      expect(names, contains('graph_nodes'));
      expect(names, contains('graph_edges'));
      expect(names, contains('graph_node_sources'));
      expect(names, contains('graph_edge_evidence'));
      expect(names, contains('graph_build_jobs'));
      expect(names, contains('graph_view_prefs'));

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      final indexNames = indexes.map((row) => row['name']).toSet();
      expect(indexNames, contains('idx_graph_nodes_user'));
      expect(indexNames, contains('idx_graph_edges_source'));
      expect(indexNames, contains('idx_graph_node_sources_kb'));
      expect(indexNames, contains('idx_graph_edge_evidence_edge'));
    });

    test('迁移不删除既有表：knowledge_concepts 仍然存在', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables.map((row) => row['name']).toSet();
      expect(names, contains('knowledge_concepts'));
      expect(names, contains('knowledge_concept_links'));
      expect(names, contains('import_records'));
    });
  });

  group('写入与去重', () {
    test('抽取结果落库并记录来源', () async {
      final source = await addSource(library: 11);
      final summary = await write(
        user: 1,
        library: 11,
        document: source.documentId,
        record: source.importRecordId,
        draft: calculusDraft,
      );

      expect(summary.createdNodeCount, 3);
      expect(summary.createdEdgeCount, 3);
      expect(summary.skippedEdges, isEmpty);

      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.nodes, hasLength(3));
      expect(view.edges, hasLength(3));
      for (final node in view.nodes) {
        expect(node.libraryIds, [11]);
        expect(node.isShared, isFalse);
      }
    });

    test('同一实体在多本知识库只保留一个节点并保留全部来源', () async {
      final a = await addSource(library: 11, title: '高数');
      final b = await addSource(library: 12, title: '机器学习');

      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: '梯度', entityType: '概念')],
          edges: [],
        ),
      );
      await write(
        user: 1,
        library: 12,
        document: b.documentId,
        record: b.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(
              name: '梯度',
              entityType: '概念',
              description: '机器学习里的梯度',
            ),
          ],
          edges: [],
        ),
      );

      final all = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11, 12]);
      expect(all.nodes, hasLength(1), reason: '同一实体不应产生重复节点');
      expect(all.nodes.single.libraryIds.toSet(), {11, 12});
      expect(all.nodes.single.isShared, isTrue);

      final onlyFirst = await graph.fetchVisibleGraph(
        userId: 1,
        libraryIds: [11],
      );
      expect(onlyFirst.nodes, hasLength(1));
      expect(onlyFirst.nodes.single.libraryIds, [11]);
    });

    test('同名但实体类型不同不会自动合并', () async {
      final a = await addSource(library: 11);
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(name: '函数', entityType: '概念'),
            GraphNodeDraft(name: '函数', entityType: '方法'),
          ],
          edges: [],
        ),
      );
      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.nodes, hasLength(2));

      final first = view.nodes.firstWhere((n) => n.entityType == '概念');
      final candidates = await graph.findMergeCandidates(
        userId: 1,
        nodeId: first.id,
      );
      expect(candidates, hasLength(1));
      expect(candidates.single.entityType, '方法');
    });

    test('别名精确匹配会复用已有实体', () async {
      final a = await addSource(library: 11);
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(
              name: '梯度',
              entityType: '概念',
              aliases: ['gradient', '梯度向量'],
            ),
          ],
          edges: [],
        ),
      );

      final b = await addSource(library: 11, title: '第二份');
      final summary = await write(
        user: 1,
        library: 11,
        document: b.documentId,
        record: b.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: 'Gradient', entityType: '概念')],
          edges: [],
        ),
      );
      expect(summary.createdNodeCount, 0);
      expect(summary.reusedNodeCount, 1);

      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.nodes, hasLength(1));
    });

    test('重复关系只保留一条，无方向关系反向也不重复', () async {
      final a = await addSource(library: 11);
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(name: '梯度', entityType: '概念'),
            GraphNodeDraft(name: '优化算法', entityType: '算法'),
          ],
          edges: [
            GraphEdgeDraft(fromName: '梯度', toName: '优化算法', relationType: '应用于'),
            GraphEdgeDraft(fromName: '梯度', toName: '优化算法', relationType: 'applied_to'),
            GraphEdgeDraft(fromName: '优化算法', toName: '梯度', relationType: '相关'),
            GraphEdgeDraft(fromName: '梯度', toName: '优化算法', relationType: '相关'),
          ],
        ),
      );
      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.edges, hasLength(2));
      expect(
        view.edges.map((e) => e.relationType).toSet(),
        {'应用于', '相关'},
      );
      final related = view.edges.firstWhere((e) => e.relationType == '相关');
      expect(related.directed, isFalse);
    });

    test('端点无法唯一确定的关系被跳过并报告', () async {
      final a = await addSource(library: 11);
      final summary = await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: '导数', entityType: '概念')],
          edges: [
            GraphEdgeDraft(fromName: '导数', toName: '不存在的知识点', relationType: '相关'),
          ],
        ),
      );
      expect(summary.createdEdgeCount, 0);
      expect(summary.skippedEdges, hasLength(1));
      expect(summary.skippedEdges.single, contains('端点无法唯一确定'));
    });

    test('重建同一份资料不会重复累积节点', () async {
      final a = await addSource(library: 11);
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: calculusDraft,
      );
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: calculusDraft,
      );
      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.nodes, hasLength(3));
      expect(view.edges, hasLength(3));
    });
  });

  group('动态筛选', () {
    test('取消一本知识库只移除属于它的节点，共享实体保留', () async {
      final a = await addSource(library: 11, title: 'A');
      final b = await addSource(library: 12, title: 'B');
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(name: '梯度', entityType: '概念'),
            GraphNodeDraft(name: '导数', entityType: '概念'),
          ],
          edges: [
            GraphEdgeDraft(fromName: '导数', toName: '梯度', relationType: '前置知识'),
          ],
        ),
      );
      await write(
        user: 1,
        library: 12,
        document: b.documentId,
        record: b.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(name: '梯度', entityType: '概念'),
            GraphNodeDraft(name: '梯度下降', entityType: '算法'),
          ],
          edges: [
            GraphEdgeDraft(fromName: '梯度', toName: '梯度下降', relationType: '应用于'),
          ],
        ),
      );

      final both = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11, 12]);
      expect(both.nodes, hasLength(3));
      expect(both.edges, hasLength(2));

      final onlySecond = await graph.fetchVisibleGraph(
        userId: 1,
        libraryIds: [12],
      );
      expect(
        onlySecond.nodes.map((n) => n.label).toSet(),
        {'梯度', '梯度下降'},
        reason: '共享实体必须保留，专属实体被移除',
      );
      expect(onlySecond.edges, hasLength(1));

      final none = await graph.fetchVisibleGraph(userId: 1, libraryIds: []);
      expect(none.nodes, isEmpty);
    });

    test('跨库关系被标记为 cross-library', () async {
      final a = await addSource(library: 11, title: 'A');
      final b = await addSource(library: 12, title: 'B');
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: '梯度', entityType: '概念')],
          edges: [],
        ),
      );
      await write(
        user: 1,
        library: 12,
        document: b.documentId,
        record: b.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: '梯度下降', entityType: '算法')],
          edges: [],
        ),
      );
      await write(
        user: 1,
        library: null,
        document: null,
        record: null,
        origin: GraphEdgeOrigin.crossLibrary,
        replace: false,
        draft: const GraphExtractionDraft(
          nodes: [],
          edges: [
            GraphEdgeDraft(
              fromName: '梯度',
              toName: '梯度下降',
              relationType: '应用于',
              evidenceText: '梯度下降沿负梯度方向更新参数',
              confidence: 0.85,
            ),
          ],
        ),
      );

      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11, 12]);
      expect(view.edges, hasLength(1));
      expect(view.edges.single.isCrossLibrary, isTrue);
    });

    test('按名称与别名搜索，且受当前知识库范围限制', () async {
      final a = await addSource(library: 11);
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(
              name: '梯度',
              entityType: '概念',
              aliases: ['gradient'],
            ),
          ],
          edges: [],
        ),
      );

      final byName = await graph.searchNodes(
        userId: 1,
        libraryIds: [11],
        query: '梯度',
      );
      expect(byName, hasLength(1));

      final byAlias = await graph.searchNodes(
        userId: 1,
        libraryIds: [11],
        query: 'gradient',
      );
      expect(byAlias, hasLength(1));

      final outOfScope = await graph.searchNodes(
        userId: 1,
        libraryIds: [12],
        query: '梯度',
      );
      expect(outOfScope, isEmpty);
    });
  });

  group('来源追溯与删除', () {
    test('节点详情包含来源记录与邻居', () async {
      final a = await addSource(library: 11, title: '高数讲义');
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: calculusDraft,
      );
      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      final gradient = view.nodes.firstWhere((n) => n.label == '梯度');

      final detail = await graph.fetchNodeDetail(
        userId: 1,
        nodeId: gradient.id,
      );
      expect(detail, isNotNull);
      expect(detail!.sources, hasLength(1));
      expect(detail.sources.single.source.sourceDocumentId, a.documentId);
      expect(detail.sources.single.source.importRecordId, a.importRecordId);
      expect(detail.libraryNames, ['库1_1']);
      expect(detail.neighbors, hasLength(2));
      expect(detail.node.aliases, contains('gradient'));
    });

    test('删除资料只失效孤立实体，不影响其他知识库', () async {
      final a = await addSource(library: 11, title: 'A');
      final b = await addSource(library: 12, title: 'B');
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(name: '梯度', entityType: '概念'),
            GraphNodeDraft(name: '导数', entityType: '概念'),
          ],
          edges: [
            GraphEdgeDraft(fromName: '导数', toName: '梯度', relationType: '前置知识'),
          ],
        ),
      );
      await write(
        user: 1,
        library: 12,
        document: b.documentId,
        record: b.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: '梯度下降', entityType: '算法')],
          edges: [],
        ),
      );

      await SourceDocumentRepository(database: app).deleteDocument(
        userId: 1,
        documentId: a.documentId,
      );

      final libraryTwo = await graph.fetchVisibleGraph(
        userId: 1,
        libraryIds: [12],
      );
      expect(
        libraryTwo.nodes.map((n) => n.label),
        ['梯度下降'],
        reason: '其他知识库的知识点不能被误删',
      );

      final libraryOne = await graph.fetchVisibleGraph(
        userId: 1,
        libraryIds: [11],
      );
      expect(libraryOne.nodes, isEmpty);

      final archived = await db.query(
        'graph_nodes',
        columns: ['status'],
        where: 'user_id = ?',
        whereArgs: [1],
      );
      final byStatus = <String, int>{};
      for (final row in archived) {
        final status = row['status'] as String;
        byStatus[status] = (byStatus[status] ?? 0) + 1;
      }
      expect(
        byStatus['archived'],
        2,
        reason: '被删资料的专属实体应归档而不是物理删除',
      );
      expect(
        byStatus['active'],
        1,
        reason: '其他知识库的知识点必须保持可用',
      );
    });

    test('删除共享资料时，仍被其他资料引用的实体保持可用', () async {
      final a = await addSource(library: 11, title: 'A');
      final b = await addSource(library: 11, title: 'B');
      const draft = GraphExtractionDraft(
        nodes: [GraphNodeDraft(name: '梯度', entityType: '概念')],
        edges: [],
      );
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: draft,
      );
      await write(
        user: 1,
        library: 11,
        document: b.documentId,
        record: b.importRecordId,
        draft: draft,
      );

      await SourceDocumentRepository(database: app).deleteDocument(
        userId: 1,
        documentId: a.documentId,
      );

      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.nodes, hasLength(1));
      final detail = await graph.fetchNodeDetail(
        userId: 1,
        nodeId: view.nodes.single.id,
      );
      expect(detail!.sources, hasLength(1));
      expect(detail.sources.single.source.sourceDocumentId, b.documentId);
    });

    test('删除学习包会清理其页资料的图谱来源', () async {
      final batch = await DocumentBatchRepository(
        database: app,
      ).createDocumentBatch(
        userId: 1,
        libraryId: 11,
        sourceType: DocumentBatchSourceType.multiImage,
        pageSourceType: SourceDocumentSourceType.galleryImport,
        title: '学习包',
        originalFilePath: '/fixture/batch',
        pages: const [
          DocumentBatchPageDraft(
            savedPath: '/fixture/p1.png',
            title: '第1页',
            pageNumber: 1,
          ),
        ],
      );
      final pages = await DocumentBatchRepository(
        database: app,
      ).getBatchWithPages(userId: 1, batchId: batch.id);
      final pageId = pages!.pages.first.id;

      await write(
        user: 1,
        library: 11,
        document: pageId,
        record: null,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: '积分', entityType: '概念')],
          edges: [],
        ),
      );

      await DocumentBatchRepository(
        database: app,
      ).deleteBatch(userId: 1, batchId: batch.id);

      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.nodes, isEmpty);
    });
  });

  group('人工合并与审核', () {
    test('合并实体后关系迁移到父实体，来源整体并入，撤销可无损还原', () async {
      final a = await addSource(library: 11);
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(name: '导数', entityType: '概念'),
            GraphNodeDraft(name: '梯度', entityType: '概念'),
            GraphNodeDraft(name: '偏导数', entityType: '概念'),
          ],
          edges: [
            GraphEdgeDraft(fromName: '偏导数', toName: '导数', relationType: '前置知识'),
          ],
        ),
      );
      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.nodes, hasLength(3));
      expect(view.edges, hasLength(1));

      final derivative = view.nodes.firstWhere((n) => n.label == '导数');
      final gradient = view.nodes.firstWhere((n) => n.label == '梯度');

      await graph.mergeNodes(
        userId: 1,
        sourceNodeId: derivative.id,
        targetNodeId: gradient.id,
      );

      final merged = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(merged.nodes, hasLength(2), reason: '被合并的实体不再作为独立节点出现');
      expect(merged.edges, hasLength(1));
      expect(
        merged.edges.single.targetId,
        gradient.id,
        reason: '关系端点应迁移到父实体',
      );

      final detail = await graph.fetchNodeDetail(
        userId: 1,
        nodeId: gradient.id,
      );
      expect(detail!.sources, hasLength(2), reason: '子实体的来源并入父实体');
      expect(detail.neighbors, hasLength(1));

      await graph.unmergeNode(userId: 1, nodeId: derivative.id);
      final restored = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(restored.nodes, hasLength(3), reason: '撤销合并应无损还原实体与来源');
    });

    test('否决的关系不再出现在画布上', () async {
      final a = await addSource(library: 11);
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [
            GraphNodeDraft(name: '导数', entityType: '概念'),
            GraphNodeDraft(name: '积分', entityType: '概念'),
          ],
          edges: [
            GraphEdgeDraft(fromName: '导数', toName: '积分', relationType: '相关'),
          ],
        ),
      );
      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.edges, hasLength(1));
      await graph.rejectEdge(userId: 1, edgeId: view.edges.single.id);
      final after = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(after.edges, isEmpty);
      expect(after.nodes, hasLength(2), reason: '否决关系不影响实体');
    });
  });

  group('视图偏好与构建任务', () {
    test('选择状态可持久化且不会写入知识实体网络', () async {
      await graph.saveSelectedLibraries(userId: 1, libraryIds: [11, 12]);
      expect(await graph.loadSelectedLibraries(1), [11, 12]);

      final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
      expect(view.nodes, isEmpty);
      final nodes = await db.query('graph_nodes');
      expect(nodes, isEmpty, reason: '视图筛选不应混入知识实体');
    });

    test('构建任务记录状态与进度', () async {
      final jobId = await graph.createBuildJob(
        userId: 1,
        scope: GraphBuildScope.library,
        scopeId: 11,
        totalUnits: 4,
      );
      await graph.updateBuildJob(
        jobId: jobId,
        doneUnits: 2,
        totalUnits: 4,
      );
      final running = await graph.latestBuildJob(
        userId: 1,
        scope: GraphBuildScope.library,
        scopeId: 11,
      );
      expect(running!.status, GraphBuildStatus.running);
      expect(running.progress, 50);

      await graph.updateBuildJob(
        jobId: jobId,
        doneUnits: 4,
        totalUnits: 4,
        status: GraphBuildStatus.success,
        complete: true,
      );
      final done = await graph.latestBuildJob(userId: 1);
      expect(done!.status, GraphBuildStatus.success);
      expect(done.progress, 100);
      expect(done.completedAt, isNotNull);
      expect(done.isTerminal, isTrue);
    });

    test('覆盖率统计反映哪些资料还没建图谱', () async {
      final a = await addSource(library: 11, title: 'A');
      await addSource(library: 11, title: 'B');
      await write(
        user: 1,
        library: 11,
        document: a.documentId,
        record: a.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: '极限', entityType: '概念')],
          edges: [],
        ),
      );

      final coverage = await graph.libraryCoverage(userId: 1, libraryId: 11);
      expect(coverage.documentCount, 2);
      expect(coverage.coveredDocumentCount, 1);
      expect(coverage.nodeCount, 1);
      expect(coverage.isBuilt, isTrue);
      expect(coverage.isPartial, isTrue);

      final covered = await graph.coveredDocumentIds(
        userId: 1,
        libraryId: 11,
      );
      expect(covered, {a.documentId});
      expect(await graph.nodeCountsByLibrary(1), {11: 1});
    });
  });

  group('数据隔离', () {
    test('用户之间互不可见', () async {
      final mine = await addSource(user: 1, library: 11, title: '我的');
      await write(
        user: 1,
        library: 11,
        document: mine.documentId,
        record: mine.importRecordId,
        draft: const GraphExtractionDraft(
          nodes: [GraphNodeDraft(name: '梯度', entityType: '概念')],
          edges: [],
        ),
      );

      final otherUser = await graph.fetchVisibleGraph(
        userId: 2,
        libraryIds: [21, 22],
      );
      expect(otherUser.nodes, isEmpty);

      final otherSearch = await graph.searchNodes(
        userId: 2,
        libraryIds: [21],
        query: '梯度',
      );
      expect(otherSearch, isEmpty);
    });
  });
}
