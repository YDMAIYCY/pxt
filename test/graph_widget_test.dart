import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/graph_repository.dart';
import 'package:pxt1/database/models/graph_records.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/ui/pages/knowledge_graph_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';
import 'package:pxt1/ui/widgets/graph_library_picker_sheet.dart';
import 'package:pxt1/ui/widgets/knowledge_graph_canvas.dart';
import 'package:pxt1/ui/widgets/graph_node_detail_sheet.dart';

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
      'username': 'fixture',
      'password_hash': 'fixture',
      'password_salt': 'fixture',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('auth_sessions', {
      'user_id': 1,
      'session_token': 'test-session',
      'created_at': now,
    });
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: page)),
    );
    // 真实 SQLite FFI 不在 widget 假时钟内运行。
    for (var i = 0; i < 14; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 在 widget 测试里执行真实数据库操作必须包在 runAsync 中。
  Future<T> real<T>(WidgetTester tester, Future<T> Function() action) async {
    final result = await tester.runAsync(action);
    return result as T;
  }

  KnowledgeLibraryRecord library({
    int id = 11,
    String name = '高等数学',
    int color = 0xFF5B90FF,
  }) => KnowledgeLibraryRecord(
    id: id,
    userId: 1,
    name: name,
    createdAt: DateTime(2026, 10, 1),
    updatedAt: DateTime(2026, 10, 1),
    documentCount: 3,
    coverColor: color,
  );

  group('知识库选择弹窗', () {
    testWidgets('展示全部知识库，支持搜索、全选与清空', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      List<int>? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showGraphLibraryPicker(
                      context,
                      libraries: [
                        library(id: 11, name: '高等数学'),
                        library(id: 12, name: '机器学习', color: 0xFF62BBA0),
                        library(id: 13, name: '英语语法', color: 0xFFA58CE5),
                      ],
                      selectedIds: const [11],
                      nodeCounts: const {11: 24, 12: 0},
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('选择知识库'), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('机器学习'), findsOneWidget);
      expect(find.text('已选 1 本'), findsOneWidget);
      expect(find.textContaining('24 个知识点'), findsOneWidget);
      expect(
        find.textContaining('尚未建图谱'),
        findsNWidgets(2),
        reason: '没有图谱的知识库要明确标注，不能显示假数量',
      );

      // 搜索过滤
      await tester.enterText(find.byType(TextField), '机器');
      await tester.pumpAndSettle();
      expect(find.text('高等数学'), findsNothing);
      expect(find.text('机器学习'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // 全选
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 3 本'), findsOneWidget);

      // 清空
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 本'), findsOneWidget);
      expect(find.textContaining('不选择'), findsOneWidget);

      // 只选机器学习并确认
      await tester.tap(find.text('机器学习'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('确认选择'));
      await tester.pumpAndSettle();
      expect(result, [12]);
    });
  });

  group('知识点详情弹窗', () {
    GraphNodeDetail detail({
      List<GraphNodeSourceView> sources = const [],
      List<GraphNodeNeighborView> neighbors = const [],
    }) => GraphNodeDetail(
      node: GraphNodeRecord(
        id: 1,
        userId: 1,
        canonicalKey: '梯度|概念',
        canonicalName: '梯度',
        displayName: '梯度',
        entityType: '概念',
        aliases: const ['gradient'],
        status: GraphNodeStatus.active,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
        description: '多元函数的最速上升方向',
      ),
      sources: sources,
      neighbors: neighbors,
      libraryNames: const ['高等数学'],
    );

    testWidgets('展示名称、类型、同义词、来源与关联，并可发起合并确认', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      GraphNodeSheetResult? result;
      final withData = detail(
        sources: [
          GraphNodeSourceView(
            source: GraphNodeSourceRecord(
              id: 1,
              nodeId: 1,
              userId: 1,
              knowledgeBaseId: 11,
              importRecordId: 5,
              sourceDocumentId: 9,
              evidenceText: '梯度指向函数增长最快的方向',
              createdAt: DateTime(2026, 10, 1),
            ),
            libraryName: '高等数学',
            recordTitle: '高数讲义',
            documentTitle: '第1页',
          ),
        ],
        neighbors: [
          GraphNodeNeighborView(
            node: GraphNodeRecord(
              id: 2,
              userId: 1,
              canonicalKey: '梯度下降|算法',
              canonicalName: '梯度下降',
              displayName: '梯度下降',
              entityType: '算法',
              aliases: const [],
              status: GraphNodeStatus.active,
              createdAt: DateTime(2026, 10, 1),
              updatedAt: DateTime(2026, 10, 1),
            ),
            edge: GraphEdgeRecord(
              id: 3,
              userId: 1,
              sourceNodeId: 1,
              targetNodeId: 2,
              relationType: '应用于',
              directed: true,
              confidence: 0.85,
              reviewStatus: GraphEdgeReviewStatus.auto,
              origin: GraphEdgeOrigin.crossLibrary,
              createdAt: DateTime(2026, 10, 1),
              updatedAt: DateTime(2026, 10, 1),
            ),
            isOutgoing: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showGraphNodeDetailSheet(
                      context,
                      detail: withData,
                      libraryColors: const {11: Color(0xFF5B90FF)},
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('梯度'), findsOneWidget);
      expect(find.text('概念'), findsOneWidget);
      expect(find.textContaining('gradient'), findsOneWidget);
      expect(find.textContaining('多元函数的最速上升方向'), findsOneWidget);
      expect(find.text('来源知识库'), findsOneWidget);
      expect(find.text('高数讲义'), findsOneWidget);
      expect(find.textContaining('应用于'), findsOneWidget);
      expect(find.textContaining('跨库'), findsOneWidget);

      final sourceAction = find.text('查看来源');
      await tester.ensureVisible(sourceAction);
      await tester.pumpAndSettle();
      await tester.tap(sourceAction);
      await tester.pumpAndSettle();
      expect(result?.action, GraphNodeSheetAction.openSource);
      expect(result?.importRecordId, 5);
      expect(result?.documentId, 9);
    });

    testWidgets('没有来源时禁用来源按钮，AI 面试明确标注未开放', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showGraphNodeDetailSheet(
                    context,
                    detail: detail(),
                    libraryColors: const {},
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      final sourceButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('查看来源'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(sourceButton.onPressed, isNull, reason: '没有来源时不能伪装为可用');

      expect(find.text('AI 面试（暂未开放）'), findsOneWidget);
      final interviewButton = find.text('AI 面试（暂未开放）');
      await tester.ensureVisible(interviewButton);
      await tester.pumpAndSettle();
      await tester.tap(interviewButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('尚未在应用内开放'), findsOneWidget);
    });
  });

  group('知识图谱页面', () {
    testWidgets('未导入资料时给出明确的空状态，不展示示例网络', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pump(
        tester,
        KnowledgeGraphPage(userId: 1, database: app),
      );

      expect(find.text('知识图谱'), findsOneWidget);
      expect(find.text('所选知识库'), findsOneWidget);
      expect(find.textContaining('还没有导入资料'), findsOneWidget);
      expect(find.text('添加'), findsOneWidget);
      expect(find.text('查看来源'), findsNothing);
    });

    testWidgets('有真实图谱数据时展示知识点数量与图例', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final graph = GraphRepository(database: app);
      final target = await real(tester, () async {
        final database = await app.database;
        final library = await database.query(
          'knowledge_libraries',
          columns: ['id'],
          where: 'user_id = ?',
          whereArgs: [1],
          limit: 1,
        );
        final libraryId = library.isEmpty
            ? await database.insert('knowledge_libraries', {
                'user_id': 1,
                'name': '高等数学',
                'created_at': now,
                'updated_at': now,
              })
            : library.first['id'] as int;

        final document = await SourceDocumentRepository(
          database: app,
        ).createSourceDocument(
          userId: 1,
          libraryId: libraryId,
          sourceType: 'camera_capture',
          imagePath: '/fixture/a.png',
          title: '高数讲义',
        );
        await graph.persistExtraction(
          userId: 1,
          knowledgeBaseId: libraryId,
          importRecordId: null,
          sourceDocumentId: document.id,
          draft: const GraphExtractionDraft(
            nodes: [
              GraphNodeDraft(name: '函数极限', entityType: '概念'),
              GraphNodeDraft(name: '导数', entityType: '概念'),
            ],
            edges: [
              GraphEdgeDraft(
                fromName: '函数极限',
                toName: '导数',
                relationType: '前置知识',
              ),
            ],
          ),
        );
        return libraryId;
      });

      await pump(
        tester,
        KnowledgeGraphPage(
          userId: 1,
          database: app,
          initialLibraryIds: [target],
        ),
      );

      expect(find.text('2 个知识点'), findsOneWidget);
      expect(find.textContaining('还没有导入资料'), findsNothing);
      expect(find.textContaining('还没有生成知识图谱'), findsNothing);
      expect(find.text('高等数学'), findsWidgets, reason: '图例与标签应显示真实知识库名');
    });

    testWidgets('取消选择知识库后回到未选择状态', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pump(
        tester,
        KnowledgeGraphPage(userId: 1, database: app),
      );

      // 默认会自动选中第一本知识库，取消后应回到空状态。
      final removeButton = find.byTooltip('取消选择');
      expect(removeButton, findsOneWidget);
      await tester.tap(removeButton);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.textContaining('还没有选择知识库'), findsOneWidget);
    });
  });

  group('知识图谱画布', () {
    GraphViewData singleNodeGraph() => const GraphViewData(
      nodes: [
        GraphViewNode(
          id: 1,
          label: '梯度',
          entityType: '概念',
          description: null,
          libraryIds: [11],
          primaryLibraryId: 11,
          status: 'active',
          degree: 0,
          aliases: [],
        ),
      ],
      edges: [],
      libraryIds: [11],
      totalNodeCount: 1,
    );

    testWidgets('点击节点触发节点回调，点击空白触发空白回调', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = GraphCanvasController();
      GraphViewNode? tappedNode;
      var backgroundTaps = 0;
      var settled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: KnowledgeGraphCanvas(
              data: singleNodeGraph(),
              libraryColors: const {11: Color(0xFF5B90FF)},
              controller: controller,
              onNodeTap: (node) => tappedNode = node,
              onBackgroundTap: () => backgroundTaps++,
              onLayoutSettled: () => settled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(settled, isTrue, reason: '布局完成后应回调通知');

      controller.focusNode(1, animate: false);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(180, 300));
      await tester.pump();
      expect(tappedNode?.id, 1, reason: '命中节点应回传真实实体');

      await tester.tapAt(const Offset(6, 6));
      await tester.pump();
      expect(backgroundTaps, 1, reason: '点击空白区域应清除高亮');
    });

    testWidgets('控制器缩放与复位不抛异常', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = GraphCanvasController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: KnowledgeGraphCanvas(
              data: singleNodeGraph(),
              libraryColors: const {11: Color(0xFF5B90FF)},
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.zoomIn();
      await tester.pumpAndSettle();
      controller.zoomOut();
      await tester.pumpAndSettle();
      controller.resetView(animate: false);
      await tester.pumpAndSettle();
      expect(find.byType(KnowledgeGraphCanvas), findsOneWidget);
    });

    testWidgets('25 个节点时初始视图完整显示整张图，且缩放仍在可读范围', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = GraphCanvasController();
      final nodes = List<GraphViewNode>.generate(
        25,
        (index) => GraphViewNode(
          id: index + 1,
          label: '知识点$index',
          entityType: '概念',
          description: null,
          libraryIds: const [11],
          primaryLibraryId: 11,
          status: GraphNodeStatus.active,
          degree: 2,
          aliases: const [],
        ),
      );
      final edges = List<GraphViewEdge>.generate(
        24,
        (index) => GraphViewEdge(
          id: index + 1,
          sourceId: index + 1,
          targetId: index + 2,
          relationType: '相关',
          directed: false,
          confidence: 0.6,
          isCrossLibrary: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: KnowledgeGraphCanvas(
              data: GraphViewData(
                nodes: nodes,
                edges: edges,
                libraryIds: const [11],
                totalNodeCount: nodes.length,
              ),
              libraryColors: const {11: Color(0xFF5B90FF)},
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final world = controller.debugWorld;
      final viewport = controller.debugViewport;
      final scale = controller.debugScale;
      expect(world.width, greaterThan(0));
      expect(viewport.width, greaterThan(0));
      expect(
        world.width * scale,
        lessThanOrEqualTo(viewport.width + 1),
        reason: '复位视图必须能完整看到整张图',
      );
      expect(
        world.height * scale,
        lessThanOrEqualTo(viewport.height + 1),
        reason: '复位视图必须能完整看到整张图',
      );
      expect(
        scale,
        greaterThanOrEqualTo(0.3),
        reason: '小规模图谱的初始缩放不应小到看不清',
      );
    });

    testWidgets('数据变化时保留已有节点位置，不清空重排', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = GraphCanvasController();
      var settleCount = 0;

      Widget build(GraphViewData data) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: KnowledgeGraphCanvas(
            data: data,
            libraryColors: const {11: Color(0xFF5B90FF)},
            controller: controller,
            onLayoutSettled: () => settleCount++,
          ),
        ),
      );

      await tester.pumpWidget(build(singleNodeGraph()));
      await tester.pumpAndSettle();
      expect(settleCount, 1);

      await tester.pumpWidget(
        build(
          const GraphViewData(
            nodes: [
              GraphViewNode(
                id: 1,
                label: '梯度',
                entityType: '概念',
                description: null,
                libraryIds: [11],
                primaryLibraryId: 11,
                status: 'active',
                degree: 1,
                aliases: [],
              ),
              GraphViewNode(
                id: 2,
                label: '导数',
                entityType: '概念',
                description: null,
                libraryIds: [11],
                primaryLibraryId: 11,
                status: 'active',
                degree: 1,
                aliases: [],
              ),
            ],
            edges: [
              GraphViewEdge(
                id: 5,
                sourceId: 2,
                targetId: 1,
                relationType: '前置知识',
                directed: true,
                confidence: 0.8,
                isCrossLibrary: false,
              ),
            ],
            libraryIds: [11],
            totalNodeCount: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(settleCount, 2, reason: '新增节点后应重新求解一次布局');
      expect(find.byType(KnowledgeGraphCanvas), findsOneWidget);
    });
  });
}
