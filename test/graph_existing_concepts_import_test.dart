import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/graph_repository.dart';
import 'package:pxt1/database/knowledge_graph_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/generator/graph_builder_service.dart';

// ========== 既有知识点零成本导入测试 ==========
// 已有资料初始化图谱时不应重复调用模型：直接复用已经抽取过的知识点。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase app;
  late Database db;
  const now = '2026-10-14T01:00:00.000Z';

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'u',
      'password_hash': 'x',
      'password_salt': 'x',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('knowledge_libraries', {
      'id': 11,
      'user_id': 1,
      'name': '高等数学',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addDocument({String title = '高数讲义'}) async {
    final document = await SourceDocumentRepository(
      database: app,
    ).createSourceDocument(
      userId: 1,
      libraryId: 11,
      sourceType: 'camera_capture',
      imagePath: '/fixture/$title.png',
      title: title,
    );
    return document.id;
  }

  Future<void> seedExistingConcepts({
    required int documentId,
    required List<Map<String, String>> concepts,
    required List<List<String>> links,
  }) async {
    final rows = await db.query(
      'source_documents',
      columns: ['import_record_id'],
      where: 'id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    await KnowledgeGraphRepository(database: app).replaceGraphForDocument(
      userId: 1,
      libraryId: 11,
      documentId: documentId,
      draft: KnowledgeGraphDraft(
        concepts: concepts
            .map(
              (item) => KnowledgeConceptDraft(
                name: item['name'] ?? '',
                summary: item['summary'] ?? '',
                evidenceText: item['evidence'] ?? '',
                masteryScore: 40,
                weaknessScore: 60,
              ),
            )
            .toList(growable: false),
        links: links
            .map(
              (pair) => KnowledgeConceptLinkDraft(
                fromName: pair[0],
                toName: pair[1],
                relationLabel: pair.length > 2 ? pair[2] : '相关',
              ),
            )
            .toList(growable: false),
      ),
    );
    expect(rows, isNotEmpty);
  }

  test('导入既有知识点不调用模型，并建立真实来源映射', () async {
    final documentId = await addDocument();
    await seedExistingConcepts(
      documentId: documentId,
      concepts: [
        {'name': '函数极限', 'summary': '函数趋近某点时的取值趋势', 'evidence': '当 x 趋近 a'},
        {'name': '导数', 'summary': '函数的变化率', 'evidence': '导数是差商的极限'},
      ],
      links: [
        ['函数极限', '导数', '前置知识'],
      ],
    );

    final builder = KnowledgeGraphBuilder(database: app);
    final summary = await builder.importExistingConceptsForLibrary(
      userId: 1,
      libraryId: 11,
    );

    expect(summary.createdNodeCount, 2);
    expect(summary.createdEdgeCount, 1);

    final graph = GraphRepository(database: app);
    final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
    expect(view.nodes, hasLength(2));
    expect(view.edges, hasLength(1));
    expect(view.edges.single.relationType, '前置知识');

    final node = view.nodes.firstWhere((n) => n.label == '函数极限');
    final detail = await graph.fetchNodeDetail(userId: 1, nodeId: node.id);
    expect(detail!.sources.single.source.sourceDocumentId, documentId);
    expect(
      detail.sources.single.source.evidenceText,
      contains('当 x 趋近 a'),
    );
  });

  test('重复导入是幂等的，不会累积重复节点', () async {
    final documentId = await addDocument();
    await seedExistingConcepts(
      documentId: documentId,
      concepts: [
        {'name': '积分', 'summary': '', 'evidence': ''},
      ],
      links: const [],
    );

    final builder = KnowledgeGraphBuilder(database: app);
    await builder.importExistingConceptsForLibrary(userId: 1, libraryId: 11);
    await builder.importExistingConceptsForLibrary(userId: 1, libraryId: 11);

    final view = await GraphRepository(
      database: app,
    ).fetchVisibleGraph(userId: 1, libraryIds: [11]);
    expect(view.nodes, hasLength(1));
    final detail = await GraphRepository(database: app).fetchNodeDetail(
      userId: 1,
      nodeId: view.nodes.single.id,
    );
    expect(detail!.sources, hasLength(1));
  });

  test('没有既有知识点时返回零，不产生任何节点', () async {
    await addDocument();
    final summary = await KnowledgeGraphBuilder(
      database: app,
    ).importExistingConceptsForLibrary(userId: 1, libraryId: 11);
    expect(summary.createdNodeCount, 0);
    final view = await GraphRepository(
      database: app,
    ).fetchVisibleGraph(userId: 1, libraryIds: [11]);
    expect(view.nodes, isEmpty);
  });

  test('同一知识点出现在两份资料时合并为一个节点并保留两条来源', () async {
    final first = await addDocument(title: '第一份');
    final second = await addDocument(title: '第二份');
    for (final documentId in [first, second]) {
      await seedExistingConcepts(
        documentId: documentId,
        concepts: [
          {'name': '梯度', 'summary': '', 'evidence': ''},
        ],
        links: const [],
      );
    }

    await KnowledgeGraphBuilder(
      database: app,
    ).importExistingConceptsForLibrary(userId: 1, libraryId: 11);

    final graph = GraphRepository(database: app);
    final view = await graph.fetchVisibleGraph(userId: 1, libraryIds: [11]);
    expect(view.nodes, hasLength(1), reason: '同名同类型实体必须复用');
    final detail = await graph.fetchNodeDetail(
      userId: 1,
      nodeId: view.nodes.single.id,
    );
    expect(detail!.sources, hasLength(2));
  });

  test('只有另一本知识库的资料不会被导入', () async {
    await db.insert('knowledge_libraries', {
      'id': 22,
      'user_id': 1,
      'name': '机器学习',
      'created_at': now,
      'updated_at': now,
    });
    final document = await SourceDocumentRepository(
      database: app,
    ).createSourceDocument(
      userId: 1,
      libraryId: 22,
      sourceType: 'camera_capture',
      imagePath: '/fixture/ml.png',
      title: '机器学习讲义',
    );
    await KnowledgeGraphRepository(database: app).replaceGraphForDocument(
      userId: 1,
      libraryId: 22,
      documentId: document.id,
      draft: const KnowledgeGraphDraft(
        concepts: [
          KnowledgeConceptDraft(
            name: '梯度下降',
            summary: '',
            evidenceText: '',
            masteryScore: 0,
            weaknessScore: 0,
          ),
        ],
        links: [],
      ),
    );

    await KnowledgeGraphBuilder(
      database: app,
    ).importExistingConceptsForLibrary(userId: 1, libraryId: 11);

    final view = await GraphRepository(
      database: app,
    ).fetchVisibleGraph(userId: 1, libraryIds: [11]);
    expect(view.nodes, isEmpty, reason: '导入必须限定在目标知识库内');

    final other = await GraphRepository(
      database: app,
    ).fetchVisibleGraph(userId: 1, libraryIds: [22]);
    expect(other.nodes, isEmpty, reason: '未导入的库保持未构建状态');
  });

  test('GraphBuildOutcome 摘要区分复用与模型抽取', () {
    const outcome = GraphBuildOutcome(
      processedDocuments: 1,
      skippedDocuments: 0,
      reusedDocuments: 3,
      createdNodeCount: 9,
      createdEdgeCount: 4,
      failures: [],
    );
    expect(outcome.summary, contains('复用 3 份资料'));
    expect(outcome.summary, contains('模型抽取 1 份资料'));
    expect(outcome.summary, contains('新增 9 个知识点'));
  });
}
