import 'dart:async';

import 'package:flutter/material.dart';

import '../../database/app_database.dart';
import '../../database/auth_repository.dart';
import '../../database/graph_repository.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/graph_records.dart';
import '../../database/models/knowledge_library_record.dart';
import '../../database/models/llm_provider_config.dart';
import '../../graph/graph_style.dart';
import '../../generator/graph_builder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/graph_library_picker_sheet.dart';
import '../widgets/graph_node_detail_sheet.dart';
import '../widgets/knowledge_graph_canvas.dart';
import '../widgets/premium_app_chrome.dart';
import 'document_detail_page.dart';
import 'import_record_detail_page.dart';

// ========== 跨知识库动态知识图谱页面 ==========
// 只保留两部分：顶部所选知识库 + 图谱主画布。底部沿用应用原有导航栏。
// 所有节点与关系都来自本地已持久化的真实图谱数据，切换知识库不重新调用大模型。

class KnowledgeGraphPage extends StatefulWidget {
  const KnowledgeGraphPage({
    this.initialLibraryIds = const <int>[],
    this.userId,
    this.database,
    super.key,
  });

  final List<int> initialLibraryIds;
  final int? userId;
  final AppDatabase? database;

  @override
  State<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends State<KnowledgeGraphPage> {
  late final GraphRepository _graphRepository;
  late final KnowledgeLibraryRepository _libraryRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final KnowledgeGraphBuilder _builder;
  final GraphCanvasController _canvasController = GraphCanvasController();

  int? _userId;
  List<KnowledgeLibraryRecord> _libraries = const <KnowledgeLibraryRecord>[];
  List<int> _selectedLibraryIds = <int>[];
  Map<int, int> _nodeCounts = const <int, int>{};

  GraphViewData _graph = const GraphViewData.empty();
  GraphLibraryCoverage? _coverage;

  bool _loading = true;
  String? _loadError;

  int? _selectedNodeId;
  int? _selectedEdgeId;
  Set<int> _highlightedNodeIds = const <int>{};

  bool _searchOpen = false;
  List<GraphViewNode> _searchResults = const <GraphViewNode>[];

  bool _fullscreen = false;

  bool _building = false;
  String _buildMessage = '';
  GraphBuildCancellation? _cancellation;

  @override
  void initState() {
    super.initState();
    _graphRepository = GraphRepository(database: widget.database);
    _libraryRepository = KnowledgeLibraryRepository(database: widget.database);
    _llmConfigRepository = LlmConfigRepository(database: widget.database);
    _builder = KnowledgeGraphBuilder(
      graphRepository: _graphRepository,
      database: widget.database,
    );
    _selectedLibraryIds = List<int>.from(widget.initialLibraryIds);
    _bootstrap();
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  // ================= 初始化 =================

  Future<void> _bootstrap() async {
    try {
      final auth = AuthRepository(database: widget.database);
      await auth.ensureInitialized();
      final user = await auth.getCurrentUserProfile();
      if (user == null) throw StateError('登录状态已失效');
      final userId = widget.userId ?? user.id;

      final libraries = await _libraryRepository.fetchLibraries(userId);
      final nodeCounts = await _graphRepository.nodeCountsByLibrary(userId);

      if (!mounted) return;
      _userId = userId;
      _libraries = libraries;
      _nodeCounts = nodeCounts;
      await _restoreSelection(userId);
      await _reloadGraph();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$error';
      });
    }
  }

  /// 恢复上次选择，但只在选择仍然有效时采用；不会把用户选择永久写死。
  Future<void> _restoreSelection(int userId) async {
    final validIds = _libraries.map((library) => library.id).toSet();
    final persisted = await _graphRepository.loadSelectedLibraries(userId);
    final restored = persisted
        .where(validIds.contains)
        .toList(growable: false);

    final initial = _selectedLibraryIds
        .where(validIds.contains)
        .toList(growable: false);

    final resolved = initial.isNotEmpty
        ? initial
        : (restored.isNotEmpty
              ? restored
              : (validIds.isEmpty ? <int>[] : <int>[_libraries.first.id]));

    _selectedLibraryIds = resolved;
  }

  Future<void> _reloadGraph() async {
    final userId = _userId;
    if (userId == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final graph = await _graphRepository.fetchVisibleGraph(
        userId: userId,
        libraryIds: _selectedLibraryIds,
      );
      final coverage = _selectedLibraryIds.length == 1
          ? await _graphRepository.libraryCoverage(
              userId: userId,
              libraryId: _selectedLibraryIds.first,
            )
          : null;
      if (!mounted) return;
      setState(() {
        _graph = graph;
        _coverage = coverage;
        _loading = false;
        if (_selectedNodeId != null &&
            !graph.nodes.any((node) => node.id == _selectedNodeId)) {
          _selectedNodeId = null;
          _highlightedNodeIds = const <int>{};
        }
      });
      await _graphRepository.saveSelectedLibraries(
        userId: userId,
        libraryIds: _selectedLibraryIds,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$error';
      });
    }
  }

  // ================= 知识库选择 =================

  Future<void> _openLibraryPicker() async {
    final userId = _userId;
    if (userId == null) return;
    final result = await showGraphLibraryPicker(
      context,
      libraries: _libraries,
      selectedIds: _selectedLibraryIds,
      nodeCounts: _nodeCounts,
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedLibraryIds = result;
      _selectedNodeId = null;
      _selectedEdgeId = null;
      _highlightedNodeIds = const <int>{};
    });
    await _reloadGraph();
  }

  Future<void> _removeLibrary(int libraryId) async {
    setState(() {
      _selectedLibraryIds = _selectedLibraryIds
          .where((id) => id != libraryId)
          .toList(growable: false);
      _selectedNodeId = null;
      _selectedEdgeId = null;
      _highlightedNodeIds = const <int>{};
    });
    await _reloadGraph();
  }

  // ================= 构建 =================

  Future<LlmProviderConfig?> _llmConfig() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      return await _llmConfigRepository.getByUserId(userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _buildSelectedLibraries({bool force = false}) async {
    final userId = _userId;
    if (userId == null || _selectedLibraryIds.isEmpty || _building) return;

    final config = await _llmConfig();
    if (config == null) {
      if (!mounted) return;
      _showMessage('还没有配置大模型，请先到「我的」页填写 API Key。');
      return;
    }

    final cancellation = GraphBuildCancellation();
    setState(() {
      _building = true;
      _buildMessage = '准备构建…';
      _cancellation = cancellation;
    });

    int? jobId;
    try {
      jobId = await _graphRepository.createBuildJob(
        userId: userId,
        scope: GraphBuildScope.library,
        scopeId: _selectedLibraryIds.length == 1
            ? _selectedLibraryIds.first
            : null,
        totalUnits: 0,
        modelVersion: config.effectiveModel,
      );

      var processed = 0;
      final summaries = <String>[];
      var failures = <String>[];
      for (final libraryId in _selectedLibraryIds) {
        if (cancellation.isCancelled) break;
        final outcome = await _builder.buildForLibrary(
          userId: userId,
          libraryId: libraryId,
          llmConfig: config,
          force: force,
          cancellation: cancellation,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _buildMessage =
                  '${_libraryName(libraryId)}：${progress.message}';
            });
          },
        );
        processed += outcome.processedDocuments;
        summaries.add('${_libraryName(libraryId)}：${outcome.summary}');
        failures = [...failures, ...outcome.failures];
      }

      await _graphRepository.updateBuildJob(
        jobId: jobId,
        doneUnits: processed,
        totalUnits: processed,
        status: failures.isNotEmpty
            ? GraphBuildStatus.failed
            : GraphBuildStatus.success,
        errorMessage: failures.isEmpty ? null : failures.take(3).join('；'),
        complete: true,
      );

      if (!mounted) return;
      _showMessage(
        failures.isEmpty
            ? '图谱构建完成 —— ${summaries.join('；')}'
            : '构建完成，但有 ${failures.length} 份失败：${failures.first}',
      );
    } catch (error) {
      if (jobId != null) {
        await _graphRepository.updateBuildJob(
          jobId: jobId,
          status: GraphBuildStatus.failed,
          errorMessage: '$error',
          complete: true,
        );
      }
      if (mounted) _showMessage('构建失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _building = false;
          _buildMessage = '';
          _cancellation = null;
        });
      }
      await _reloadGraph();
    }
  }

  Future<void> _discoverCrossLibraryRelations() async {
    final userId = _userId;
    if (userId == null || _building || _selectedLibraryIds.length < 2) return;

    final config = await _llmConfig();
    if (config == null) {
      if (!mounted) return;
      _showMessage('还没有配置大模型，请先到「我的」页填写 API Key。');
      return;
    }

    setState(() {
      _building = true;
      _buildMessage = '正在发现跨库关系…';
    });
    try {
      final outcome = await _builder.discoverCrossLibraryRelations(
        userId: userId,
        libraryIds: _selectedLibraryIds,
        llmConfig: config,
      );
      if (!mounted) return;
      if (outcome.hasFailures) {
        _showMessage(outcome.failures.first);
      } else if (outcome.createdEdgeCount == 0) {
        _showMessage(
          '模型没有找到有依据的跨库关系（已比对 ${outcome.candidateCount} 组候选）。',
        );
      } else {
        _showMessage('新增 ${outcome.createdEdgeCount} 条跨库关系');
      }
    } catch (error) {
      if (mounted) _showMessage('跨库关系发现失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _building = false;
          _buildMessage = '';
        });
      }
      await _reloadGraph();
    }
  }

  void _cancelBuild() {
    _cancellation?.cancel();
    setState(() => _buildMessage = '正在取消…');
  }

  /// 强制重建：资料或 OCR 文本改动后，让图谱重新对齐当前内容。
  /// 会重新调用模型，因此先明确告知成本。
  Future<void> _rebuildWithConfirm() async {
    if (_selectedLibraryIds.isEmpty || _building) return;
    if (_graph.nodes.isEmpty) {
      await _buildSelectedLibraries();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新构建知识图谱？'),
        content: const Text(
          '会重新调用大模型抽取所选知识库的资料，用于同步你修改过的 OCR 文本或新增成果。'
          '已有的实体与关系会复用，不会重复创建。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('开始重建'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _buildSelectedLibraries(force: true);
  }

  // ================= 交互 =================

  void _onNodeTap(GraphViewNode node) {
    final connected = <int>{node.id};
    for (final edge in _graph.edges) {
      if (edge.sourceId == node.id) connected.add(edge.targetId);
      if (edge.targetId == node.id) connected.add(edge.sourceId);
    }
    setState(() {
      _selectedNodeId = node.id;
      _selectedEdgeId = null;
      _highlightedNodeIds = connected;
    });
    _openNodeDetail(node.id);
  }

  void _onEdgeTap(GraphViewEdge edge) {
    setState(() {
      _selectedEdgeId = edge.id;
      _selectedNodeId = null;
      _highlightedNodeIds = {edge.sourceId, edge.targetId};
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedNodeId = null;
      _selectedEdgeId = null;
      _highlightedNodeIds = const <int>{};
    });
  }

  Future<void> _openNodeDetail(int nodeId) async {
    final userId = _userId;
    if (userId == null) return;
    final detail = await _graphRepository.fetchNodeDetail(
      userId: userId,
      nodeId: nodeId,
    );
    if (detail == null || !mounted) return;
    final candidates = await _graphRepository.findMergeCandidates(
      userId: userId,
      nodeId: nodeId,
    );
    if (!mounted) return;

    final result = await showGraphNodeDetailSheet(
      context,
      detail: detail,
      libraryColors: _libraryColors(),
      mergeCandidates: candidates,
      // 应用内尚无 AI 面试入口，详情里明确标注为未开放。
      aiInterviewAvailable: false,
    );
    if (result == null || !mounted) return;

    switch (result.action) {
      case GraphNodeSheetAction.openSource:
      case GraphNodeSheetAction.openKnowledgeCard:
        await _openSource(
          importRecordId: result.importRecordId,
          documentId: result.documentId,
        );
      case GraphNodeSheetAction.focusNeighbors:
        final target = result.neighborNodeId;
        if (target != null) {
          setState(() {
            _selectedNodeId = target;
            _highlightedNodeIds = _neighborsOf(target);
          });
          _canvasController.focusNode(target);
        } else {
          _canvasController.focusNode(nodeId);
        }
      case GraphNodeSheetAction.confirmMerge:
        final mergeInto = result.mergeIntoNodeId;
        if (mergeInto != null) {
          await _graphRepository.mergeNodes(
            userId: userId,
            sourceNodeId: nodeId,
            targetNodeId: mergeInto,
          );
          if (!mounted) return;
          _showMessage('已合并为一个知识实体');
          await _reloadGraph();
        }
      case GraphNodeSheetAction.startAiInterview:
        break;
      case GraphNodeSheetAction.openRelation:
        break;
    }
  }

  Set<int> _neighborsOf(int nodeId) {
    final connected = <int>{nodeId};
    for (final edge in _graph.edges) {
      if (edge.sourceId == nodeId) connected.add(edge.targetId);
      if (edge.targetId == nodeId) connected.add(edge.sourceId);
    }
    return connected;
  }

  Future<void> _openSource({
    required int? importRecordId,
    required int? documentId,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    if (importRecordId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImportRecordDetailPage(
            recordId: importRecordId,
            userId: userId,
            database: widget.database,
          ),
        ),
      );
      return;
    }
    if (documentId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocumentDetailPage(documentId: documentId),
        ),
      );
      return;
    }
    if (mounted) _showMessage('这条知识点还没有可跳转的来源资料。');
  }

  Future<void> _runSearch(String query) async {
    final userId = _userId;
    if (userId == null || query.trim().isEmpty) {
      setState(() => _searchResults = const <GraphViewNode>[]);
      return;
    }
    final results = await _graphRepository.searchNodes(
      userId: userId,
      libraryIds: _selectedLibraryIds,
      query: query,
    );
    if (!mounted) return;
    setState(() => _searchResults = results);
  }

  void _focusSearchResult(GraphViewNode node) {
    setState(() {
      _selectedNodeId = node.id;
      _highlightedNodeIds = _neighborsOf(node.id);
      _searchOpen = false;
      _searchResults = const <GraphViewNode>[];
    });
    _canvasController.focusNode(node.id);
  }

  /// 每本知识库一个颜色，保证不同知识库在图谱上可区分。
  /// 优先用知识库自己的封面主题色，重复时按 id 顺序分配不同的主题色。
  Map<int, Color> _libraryColors() =>
      GraphPalette.assignLibraryColors(_libraries);

  String _libraryName(int libraryId) {
    for (final library in _libraries) {
      if (library.id == libraryId) return library.name;
    }
    return '知识库';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ================= 构建 UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PremiumPageBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              if (!_fullscreen) _buildLibraryPanel(),
              Expanded(child: _buildCanvasArea()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            tooltip: '返回',
          ),
          const Expanded(
            child: Text(
              '知识图谱',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          IconButton(
            onPressed: _building ? null : _rebuildWithConfirm,
            icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            tooltip: '重新构建图谱',
          ),
          IconButton(
            onPressed: () => _canvasController.resetView(),
            icon: const Icon(Icons.center_focus_strong_rounded, size: 20),
            tooltip: '复位视图',
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.cardSoftList,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.layers_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 7),
                Text('所选知识库', style: AppTextStyles.h3(context)),
                const Spacer(),
                if (_graph.nodes.isNotEmpty)
                  Text(
                    '${_graph.nodes.length} 个知识点',
                    style: AppTextStyles.caption(context),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ..._selectedLibraryIds.map(_buildLibraryChip),
                  _buildAddChip(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryChip(int libraryId) {
    final colors = _libraryColors();
    final accent = colors[libraryId] ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: Color.lerp(accent, Colors.white, 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              _libraryName(libraryId),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color.lerp(accent, AppColors.ink, 0.35),
              ),
            ),
            IconButton(
              onPressed: () => _removeLibrary(libraryId),
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(
                Icons.close_rounded,
                color: accent.withValues(alpha: 0.75),
              ),
              tooltip: '取消选择',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: _openLibraryPicker,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: const BorderSide(color: AppColors.border),
          foregroundColor: AppColors.textSecondary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        icon: const Icon(Icons.add_rounded, size: 17),
        label: const Text('添加'),
      ),
    );
  }

  Widget _buildCanvasArea() {
    // 底部预留浮动导航栏的高度，避免缩放按钮和图例被遮挡。
    return Padding(
      padding: EdgeInsets.fromLTRB(14, _fullscreen ? 4 : 0, 14, 96),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.cardSoftList,
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _buildCanvasBody()),
            Positioned(top: 12, right: 12, child: _buildCanvasToolbar()),
            if (_searchOpen) Positioned(
              top: 12,
              left: 12,
              right: 64,
              child: _buildSearchField(),
            ),
            if (_searchOpen && _searchResults.isNotEmpty)
              Positioned(
                top: 62,
                left: 12,
                right: 12,
                child: _buildSearchResults(),
              ),
            if (!_fullscreen && _graph.nodes.isNotEmpty && !_searchOpen)
              Positioned(bottom: 14, left: 14, child: _buildLegend()),
            if (_graph.nodes.isNotEmpty)
              Positioned(bottom: 14, right: 14, child: _buildZoomControls()),
            if (_building) Positioned.fill(child: _buildBuildOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _CenteredHint(
        icon: Icons.error_outline_rounded,
        title: '图谱加载失败',
        message: _loadError!,
        actionLabel: '重试',
        onAction: _reloadGraph,
      );
    }
    if (_libraries.isEmpty) {
      return const _CenteredHint(
        icon: Icons.library_books_outlined,
        title: '还没有知识库',
        message: '先在「知识库」里创建一本知识库并导入资料，再回来建立知识图谱。',
      );
    }
    if (_selectedLibraryIds.isEmpty) {
      return _CenteredHint(
        icon: Icons.filter_alt_off_outlined,
        title: '还没有选择知识库',
        message: '选择一本或多本知识库，系统会从这些资料里抽取知识点与关系。',
        actionLabel: '选择知识库',
        onAction: _openLibraryPicker,
      );
    }
    if (_graph.nodes.isEmpty) {
      return _buildNotBuiltState();
    }
    return KnowledgeGraphCanvas(
      data: _graph,
      libraryColors: _libraryColors(),
      controller: _canvasController,
      selectedNodeId: _selectedNodeId,
      highlightedNodeIds: _highlightedNodeIds,
      selectedEdgeId: _selectedEdgeId,
      onNodeTap: _onNodeTap,
      onEdgeTap: _onEdgeTap,
      onBackgroundTap: _clearSelection,
    );
  }

  Widget _buildNotBuiltState() {
    final coverage = _coverage;
    final documentCount = coverage?.documentCount ?? 0;
    final hasDocuments = documentCount > 0;
    return _CenteredHint(
      icon: Icons.hub_outlined,
      title: hasDocuments ? '这些知识库还没有生成知识图谱' : '所选知识库还没有导入资料',
      message: hasDocuments
          ? '会先把已有资料里已经抽取过的知识点直接导入图谱，'
                '只对还没有知识点的资料调用大模型，避免重复消耗 token。'
          : '先导入讲义或拍照识别，再回来建立知识图谱。',
      actionLabel: hasDocuments ? '生成知识图谱' : null,
      onAction: hasDocuments ? _buildSelectedLibraries : null,
    );
  }

  Widget _buildCanvasToolbar() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CanvasIconButton(
          icon: Icons.search_rounded,
          tooltip: '搜索知识点',
          active: _searchOpen,
          onTap: () => setState(() {
            _searchOpen = !_searchOpen;
            if (!_searchOpen) {
              _searchResults = const <GraphViewNode>[];
            }
          }),
        ),
        const SizedBox(width: 8),
        _CanvasIconButton(
          icon: _fullscreen
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          tooltip: _fullscreen ? '退出全屏' : '全屏查看',
          onTap: () => setState(() => _fullscreen = !_fullscreen),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: TextField(
        autofocus: true,
        onChanged: _runSearch,
        decoration: const InputDecoration(
          hintText: '搜索知识点名称或同义词',
          prefixIcon: Icon(Icons.search_rounded, size: 19),
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _searchResults.length,
          itemBuilder: (context, index) {
            final node = _searchResults[index];
            final accent = _libraryColors()[node.primaryLibraryId] ??
                AppColors.primary;
            return ListTile(
              dense: true,
              leading: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                [
                  node.entityType,
                  if (node.libraryIds.isNotEmpty)
                    node.libraryIds.map(_libraryName).join(' / '),
                ].join(' · '),
                style: AppTextStyles.caption(context),
              ),
              onTap: () => _focusSearchResult(node),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final colors = _libraryColors();
    final entries = _selectedLibraryIds.take(4).toList(growable: false);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: entries
            .map(
              (libraryId) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors[libraryId],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: Text(
                        _libraryName(libraryId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Column(
      children: [
        if (_selectedLibraryIds.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CanvasIconButton(
              icon: Icons.alt_route_rounded,
              tooltip: '发现跨库关系',
              onTap: _discoverCrossLibraryRelations,
            ),
          ),
        _CanvasIconButton(
          icon: Icons.add_rounded,
          tooltip: '放大',
          onTap: _canvasController.zoomIn,
        ),
        const SizedBox(height: 6),
        _CanvasIconButton(
          icon: Icons.remove_rounded,
          tooltip: '缩小',
          onTap: _canvasController.zoomOut,
        ),
        const SizedBox(height: 6),
        _CanvasIconButton(
          icon: Icons.fit_screen_rounded,
          tooltip: '适应画布',
          onTap: _canvasController.resetView,
        ),
      ],
    );
  }

  Widget _buildBuildOverlay() {
    return Container(
      color: Colors.white.withValues(alpha: 0.88),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _buildMessage.isEmpty ? '正在构建知识图谱…' : _buildMessage,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall(context),
              ),
              const SizedBox(height: 8),
              Text(
                '会逐份调用大模型抽取知识点，不会重复处理已生成的资料。',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(context),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: _cancelBuild,
                child: const Text('取消构建'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= 小组件 =================

class _CanvasIconButton extends StatelessWidget {
  const _CanvasIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? AppColors.primarySoft : Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 1.5,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 19,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.primaryLight),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h3(context),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall(context),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
