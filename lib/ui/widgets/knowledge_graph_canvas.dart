import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../database/models/graph_records.dart';
import '../../graph/force_directed_layout.dart';
import '../../graph/graph_style.dart';
import '../../graph/graph_vocabulary.dart';
import '../theme/app_theme.dart';

/// 外部控制画布：聚焦节点、复位视图、缩放。
class GraphCanvasController {
  _KnowledgeGraphCanvasState? _state;

  /// 当前视图变换快照，供测试与调试读取；渲染逻辑不依赖它。
  double debugScale = 1;
  Offset debugTranslate = Offset.zero;
  Size debugWorld = Size.zero;
  Size debugViewport = Size.zero;

  void _attach(_KnowledgeGraphCanvasState state) => _state = state;
  void _detach(_KnowledgeGraphCanvasState state) {
    if (identical(_state, state)) _state = null;
  }

  /// 把某个节点移到视野中心并高亮。
  void focusNode(int nodeId, {bool animate = true}) =>
      _state?.focusNode(nodeId, animate: animate);

  /// 恢复到能看见整张图的视图。
  void resetView({bool animate = true}) =>
      _state?.fitView(animate: animate);

  void zoomIn() => _state?.zoomBy(1.25);
  void zoomOut() => _state?.zoomBy(1 / 1.25);
}

class KnowledgeGraphCanvas extends StatefulWidget {
  const KnowledgeGraphCanvas({
    required this.data,
    required this.libraryColors,
    required this.controller,
    this.selectedNodeId,
    this.highlightedNodeIds = const <int>{},
    this.selectedEdgeId,
    this.onNodeTap,
    this.onEdgeTap,
    this.onBackgroundTap,
    this.onLayoutSettled,
    super.key,
  });

  final GraphViewData data;
  final Map<int, Color> libraryColors;
  final GraphCanvasController controller;
  final int? selectedNodeId;
  final Set<int> highlightedNodeIds;
  final int? selectedEdgeId;
  final ValueChanged<GraphViewNode>? onNodeTap;
  final ValueChanged<GraphViewEdge>? onEdgeTap;
  final VoidCallback? onBackgroundTap;
  final VoidCallback? onLayoutSettled;

  @override
  State<KnowledgeGraphCanvas> createState() => _KnowledgeGraphCanvasState();
}

class _KnowledgeGraphCanvasState extends State<KnowledgeGraphCanvas>
    with SingleTickerProviderStateMixin {
  /// 视图缩放范围：允许把大规模图谱缩到能看全。
  static const double _minScale = 0.12;
  static const double _maxScale = 3.0;

  final Map<int, ForceNode> _nodes = <int, ForceNode>{};
  final Set<int> _pinned = <int>{};
  final Map<int, int> _clusterByNode = <int, int>{};

  Size _viewport = Size.zero;
  Size _world = Size.zero;

  double _scale = 1;
  Offset _translate = Offset.zero;

  int? _draggingNodeId;

  int? _lastSignature;
  bool _needsFit = true;
  bool _settled = false;
  int _layoutGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rebuildGraph();
    });
  }

  @override
  void didUpdateWidget(covariant KnowledgeGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
    final signature = _signatureOf(widget.data);
    if (signature != _lastSignature) {
      _rebuildGraph();
    }
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    super.dispose();
  }

  int _signatureOf(GraphViewData data) {
    var hash = data.nodes.length * 31 + data.edges.length;
    for (final node in data.nodes) {
      hash = hash * 31 + node.id;
      hash = hash * 31 + node.degree;
    }
    for (final edge in data.edges) {
      hash = hash * 31 + edge.id;
    }
    return hash;
  }

  // ================= 布局 =================

  void _rebuildGraph() {
    final data = widget.data;

    final previous = Map<int, ForceNode>.from(_nodes);
    final previousCount = _nodes.length;
    _nodes.clear();
    _clusterByNode.clear();

    if (data.nodes.isEmpty) {
      setState(() {
        _settled = false;
        _lastSignature = _signatureOf(data);
      });
      return;
    }

    for (final node in data.nodes) {
      final radius = GraphPalette.nodeRadius(node);
      final existing = previous[node.id];
      _nodes[node.id] = ForceNode(
        id: node.id,
        x: existing?.x ?? 0,
        y: existing?.y ?? 0,
        pinned: _pinned.contains(node.id),
        radius: radius,
        clusterId: node.primaryLibraryId,
      );
      if (node.primaryLibraryId != null) {
        _clusterByNode[node.id] = node.primaryLibraryId!;
      }
    }

    // 新增节点如果没有历史位置，先用螺旋铺开，保证初始布局稳定。
    final fresh = _nodes.values.where((node) => node.x == 0 && node.y == 0);
    if (fresh.isNotEmpty) {
      ForceDirectedLayout.seedPositions(
        nodes: fresh.toList(growable: false),
        width: _worldOrViewport().width,
        height: _worldOrViewport().height,
      );
    }

    setState(() {
      _settled = false;
      _lastSignature = _signatureOf(data);
      // 新增节点时重新适配视图；只是移除节点时保留当前视角，避免画面跳动。
      _needsFit = _needsFit || _nodes.length > previousCount;
    });

    _runLayout();
  }

  /// 一次性求解力导向布局。节点规模上限受仓库查询限制（≤600）。
  /// 规模越大迭代越少，保证手机端单次求解时间可控。
  void _runLayout() {
    final generation = ++_layoutGeneration;
    if (_nodes.isEmpty) {
      setState(() => _settled = true);
      return;
    }
    setState(() => _settled = false);
    // 先让「正在整理布局」提示渲染一帧，再执行同步计算。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _layoutGeneration) return;
      final nodes = _nodes.values.toList(growable: false);
      final world = _worldOrViewport();
      _layoutFor(nodes.length).run(
        nodes: nodes,
        edges: _forceEdges(),
        width: world.width,
        height: world.height,
      );
      setState(() => _settled = true);
      if (_needsFit) {
        _fitViewInternal(animate: false);
      }
      widget.onLayoutSettled?.call();
    });
  }

  ForceDirectedLayout _layoutFor(int nodeCount) {
    if (nodeCount > 320) {
      return const ForceDirectedLayout(
        config: ForceLayoutConfig(iterations: 96, collisionPasses: 1),
      );
    }
    if (nodeCount > 160) {
      return const ForceDirectedLayout(
        config: ForceLayoutConfig(iterations: 150, collisionPasses: 2),
      );
    }
    return const ForceDirectedLayout();
  }

  List<ForceEdge> _forceEdges() {
    final weightByType = <String, double>{
      GraphRelationTypes.prerequisite: 1.25,
      GraphRelationTypes.dependsOn: 1.2,
      GraphRelationTypes.appliedTo: 1.1,
      GraphRelationTypes.belongsTo: 1.0,
      GraphRelationTypes.contains: 1.0,
      GraphRelationTypes.extends_: 0.95,
      GraphRelationTypes.related: 0.7,
    };
    return widget.data.edges
        .where(
          (edge) =>
              _nodes.containsKey(edge.sourceId) &&
              _nodes.containsKey(edge.targetId),
        )
        .map(
          (edge) => ForceEdge(
            source: edge.sourceId,
            target: edge.targetId,
            weight: weightByType[edge.relationType] ?? 0.9,
          ),
        )
        .toList(growable: false);
  }

  Size _worldOrViewport() {
    if (_world.width > 1 && _world.height > 1) return _world;
    if (_viewport.width > 1 && _viewport.height > 1) return _viewport;
    return const Size(720, 900);
  }

  /// 画布世界尺寸：节点越多越大，保证每个节点有足够的可读面积。
  /// 上限避免小图谱被拉得过散（fit 后仍然读得清）。
  Size _computeWorld(Size viewport) {
    final count = math.max(1, widget.data.nodes.length);
    final factor = math
        .sqrt(count / 14)
        .clamp(1.0, 3.4)
        .toDouble();
    return Size(
      math.max(viewport.width, 320) * factor,
      math.max(viewport.height, 380) * factor,
    );
  }

  // ================= 视图变换 =================

  Offset _toWorld(Offset screen) => (screen - _translate) / _scale;

  void fitView({bool animate = true}) => _fitViewInternal(animate: animate);

  /// 计算能完整显示整张图的视图变换；无法计算时返回 null。
  ({double scale, Offset translate})? _fitTarget() {
    if (_viewport.width <= 1 || _viewport.height <= 1 || _nodes.isEmpty) {
      return null;
    }
    final world = _worldOrViewport();
    if (world.width <= 1 || world.height <= 1) return null;
    final rawScale = math.min(
      _viewport.width / world.width,
      _viewport.height / world.height,
    );
    final scale = (rawScale * 0.94).clamp(_minScale, _maxScale);
    final translate = Offset(
      (_viewport.width - world.width * scale) / 2,
      (_viewport.height - world.height * scale) / 2,
    );
    return (scale: scale, translate: translate);
  }

  void _fitViewInternal({required bool animate}) {
    final target = _fitTarget();
    if (target == null) return;
    _needsFit = false;
    setState(() {
      _scale = target.scale;
      _translate = target.translate;
    });
  }

  /// 在 build 阶段直接套用 fit（此时不能 setState，但值会在本帧立即生效）。
  void _applyFitDuringBuild() {
    final target = _fitTarget();
    if (target == null) return;
    _needsFit = false;
    _scale = target.scale;
    _translate = target.translate;
  }

  void zoomBy(double factor) {
    if (_viewport.width <= 1) return;
    final focal = Offset(_viewport.width / 2, _viewport.height / 2);
    final targetScale = (_scale * factor).clamp(_minScale, _maxScale);
    final worldFocal = _toWorld(focal);
    final targetTranslate = focal - worldFocal * targetScale;
    _animateView(targetScale, targetTranslate);
  }

  void focusNode(int nodeId, {bool animate = true}) {
    final node = _nodes[nodeId];
    if (node == null || _viewport.width <= 1) return;
    final targetScale = math.max(_scale, 0.85);
    final world = _worldOrViewport();
    final desired = Offset(
      (_viewport.width - world.width * targetScale) / 2,
      (_viewport.height - world.height * targetScale) / 2,
    );
    final targetTranslate = Offset(
      desired.dx + (world.width / 2 - node.x) * targetScale,
      desired.dy + (world.height / 2 - node.y) * targetScale,
    );
    if (!animate) {
      setState(() {
        _scale = targetScale;
        _translate = targetTranslate;
      });
      return;
    }
    _animateView(targetScale, targetTranslate);
  }

  void _animateView(double targetScale, Offset targetTranslate) {
    setState(() {
      _scale = targetScale;
      _translate = targetTranslate;
    });
  }

  // ================= 手势 =================

  GraphViewNode? _hitNode(Offset world) {
    GraphViewNode? best;
    var bestDistance = double.infinity;
    for (final view in widget.data.nodes) {
      final node = _nodes[view.id];
      if (node == null) continue;
      final dx = node.x - world.dx;
      final dy = node.y - world.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance <= node.radius + 6 && distance < bestDistance) {
        bestDistance = distance;
        best = view;
      }
    }
    return best;
  }

  GraphViewEdge? _hitEdge(Offset world) {
    final threshold = 14 / _scale;
    GraphViewEdge? best;
    var bestDistance = double.infinity;
    for (final edge in widget.data.edges) {
      final from = _nodes[edge.sourceId];
      final to = _nodes[edge.targetId];
      if (from == null || to == null) continue;
      final distance = _distanceToSegment(
        world,
        Offset(from.x, from.y),
        Offset(to.x, to.y),
      );
      if (distance <= threshold && distance < bestDistance) {
        bestDistance = distance;
        best = edge;
      }
    }
    return best;
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared < 1e-6) return (point - a).distance;
    var t = ((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);
    final projection = Offset(a.dx + dx * t, a.dy + dy * t);
    return (point - projection).distance;
  }

  void _onScaleStart(ScaleStartDetails details) {
    final world = _toWorld(details.localFocalPoint);
    final node = _hitNode(world);
    _draggingNodeId = node?.id;
    if (_draggingNodeId != null) {
      _nodes[_draggingNodeId!]?.pinned = true;
      _pinned.add(_draggingNodeId!);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_draggingNodeId != null) {
      final node = _nodes[_draggingNodeId!];
      if (node == null) return;
      final delta = details.focalPointDelta / _scale;
      setState(() {
        node.x = (node.x + delta.dx).clamp(0.0, _worldOrViewport().width);
        node.y = (node.y + delta.dy).clamp(0.0, _worldOrViewport().height);
      });
      return;
    }
    setState(() {
      if (details.scale != 1.0) {
        final focal = details.localFocalPoint;
        final worldFocal = _toWorld(focal);
        final targetScale = (_scale * details.scale).clamp(
          _minScale,
          _maxScale,
        );
        _translate = focal - worldFocal * targetScale;
        _scale = targetScale;
      }
      _translate += details.focalPointDelta;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _draggingNodeId = null;
  }

  void _onTapUp(TapUpDetails details) {
    final world = _toWorld(details.localPosition);
    final node = _hitNode(world);
    if (node != null) {
      widget.onNodeTap?.call(node);
      return;
    }
    final edge = _hitEdge(world);
    if (edge != null) {
      widget.onEdgeTap?.call(edge);
      return;
    }
    widget.onBackgroundTap?.call();
  }

  // ================= 渲染 =================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 360,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 520,
        );
        if ((viewport.width - _viewport.width).abs() > 1 ||
            (viewport.height - _viewport.height).abs() > 1) {
          _viewport = viewport;
          _world = _computeWorld(viewport);
          _needsFit = true;
        }

        // 布局完成且视口已知时立即套用 fit，避免依赖回调顺序。
        if (_needsFit && _settled && _nodes.isNotEmpty) {
          _applyFitDuringBuild();
        }

        widget.controller
          ..debugScale = _scale
          ..debugTranslate = _translate
          ..debugWorld = _world
          ..debugViewport = _viewport;

        if (widget.data.nodes.isEmpty) {
          return const SizedBox.expand();
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onTapUp: _onTapUp,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GraphPainter(
                      nodes: _nodes,
                      data: widget.data,
                      libraryColors: widget.libraryColors,
                      scale: _scale,
                      translate: _translate,
                      selectedNodeId: widget.selectedNodeId,
                      selectedEdgeId: widget.selectedEdgeId,
                      highlightedNodeIds: widget.highlightedNodeIds,
                      draggingNodeId: _draggingNodeId,
                    ),
                  ),
                ),
                if (!_settled)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: const _LayoutBadge(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LayoutBadge extends StatelessWidget {
  const _LayoutBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '正在整理布局…',
            style: AppTextStyles.caption(context),
          ),
        ],
      ),
    );
  }
}

// ========== 绘制器 ==========

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.data,
    required this.libraryColors,
    required this.scale,
    required this.translate,
    required this.selectedNodeId,
    required this.selectedEdgeId,
    required this.highlightedNodeIds,
    required this.draggingNodeId,
  });

  final Map<int, ForceNode> nodes;
  final GraphViewData data;
  final Map<int, Color> libraryColors;
  final double scale;
  final Offset translate;
  final int? selectedNodeId;
  final int? selectedEdgeId;
  final Set<int> highlightedNodeIds;
  final int? draggingNodeId;

  static const double _arrowLength = 9;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    _paintBackdrop(canvas, size);
    canvas.save();
    canvas.translate(translate.dx, translate.dy);
    canvas.scale(scale);

    final isFocusMode = selectedNodeId != null || selectedEdgeId != null;
    final labelRects = <Rect>[];

    // 先画边，让节点盖在上面。
    for (final edge in data.edges) {
      final from = nodes[edge.sourceId];
      final to = nodes[edge.targetId];
      if (from == null || to == null) continue;
      _paintEdge(canvas, edge, from, to, isFocusMode, labelRects);
    }

    final ordered = data.nodes.toList(growable: false)
      ..sort((a, b) {
        final aSelected = a.id == selectedNodeId ? 1 : 0;
        final bSelected = b.id == selectedNodeId ? 1 : 0;
        return aSelected.compareTo(bSelected);
      });
    for (final view in ordered) {
      final node = nodes[view.id];
      if (node == null) continue;
      _paintNode(canvas, view, node, isFocusMode);
    }

    canvas.restore();
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFE7EEF9).withValues(alpha: 0.5);
    const gap = 26.0;
    final step = gap * scale;
    if (step < 8) return;
    for (var x = translate.dx % step; x <= size.width; x += step) {
      for (var y = translate.dy % step; y <= size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  bool _isEdgeHighlighted(GraphViewEdge edge) {
    if (edge.id == selectedEdgeId) return true;
    if (selectedNodeId == null) return false;
    return edge.sourceId == selectedNodeId || edge.targetId == selectedNodeId;
  }

  void _paintEdge(
    Canvas canvas,
    GraphViewEdge edge,
    ForceNode from,
    ForceNode to,
    bool isFocusMode,
    List<Rect> labelRects,
  ) {
    final highlighted = _isEdgeHighlighted(edge);
    final dimmed = isFocusMode && !highlighted;
    final baseColor = GraphPalette.relationColor(edge.relationType);
    final color = dimmed ? baseColor.withValues(alpha: 0.14) : baseColor;
    final strokeWidth = highlighted ? 2.4 : 1.3;

    final start = _boundaryPoint(from, Offset(to.x, to.y), 3);
    final end = _boundaryPoint(to, Offset(from.x, from.y), 3);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (GraphPalette.relationDashed(edge.relationType)) {
      _drawDashedLine(canvas, start, end, paint);
    } else {
      canvas.drawLine(start, end, paint);
    }

    if (GraphPalette.relationDirected(edge.relationType)) {
      _drawArrowHead(canvas, start, end, color, dimmed ? 0.6 : 1.0);
    }

    if (!dimmed && scale > 0.5) {
      _paintEdgeLabel(canvas, edge, start, end, color, labelRects);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 7.0;
    const gap = 5.0;
    final total = (end - start).distance;
    if (total < 1) return;
    final direction = (end - start) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final segmentEnd = math.min(travelled + dash, total);
      canvas.drawLine(
        start + direction * travelled,
        start + direction * segmentEnd,
        paint,
      );
      travelled = segmentEnd + gap;
    }
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double opacity,
  ) {
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - _arrowLength * math.cos(angle - 0.42),
        end.dy - _arrowLength * math.sin(angle - 0.42),
      )
      ..lineTo(
        end.dx - _arrowLength * math.cos(angle + 0.42),
        end.dy - _arrowLength * math.sin(angle + 0.42),
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: opacity),
    );
  }

  Offset _boundaryPoint(ForceNode node, Offset towards, double inset) {
    final dx = towards.dx - node.x;
    final dy = towards.dy - node.y;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < 1e-3) return Offset(node.x, node.y);
    final radius = math.max(0.0, node.radius + inset);
    return Offset(node.x + dx / distance * radius, node.y + dy / distance * radius);
  }

  void _paintEdgeLabel(
    Canvas canvas,
    GraphViewEdge edge,
    Offset start,
    Offset end,
    Color color,
    List<Rect> labelRects,
  ) {
    final label = edge.relationType;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    var rect = Rect.fromCenter(
      center: mid,
      width: painter.width + 12,
      height: painter.height + 7,
    );
    // 避让：与已有标签或节点重叠时沿法线方向错开。
    final normal = _normalOf(start, end);
    var attempt = 0;
    while (_overlaps(rect, labelRects) && attempt < 5) {
      attempt++;
      final offset = normal * (attempt * 15.0);
      rect = rect.shift(offset);
    }
    labelRects.add(rect);

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(999));
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.white.withValues(alpha: 0.94),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    painter.paint(
      canvas,
      Offset(rect.center.dx - painter.width / 2, rect.center.dy - painter.height / 2),
    );
  }

  Offset _normalOf(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1e-3) return const Offset(0, 1);
    return Offset(-dy / length, dx / length);
  }

  bool _overlaps(Rect rect, List<Rect> others) {
    for (final other in others) {
      if (rect.overlaps(other.inflate(2))) return true;
    }
    return false;
  }

  void _paintNode(
    Canvas canvas,
    GraphViewNode view,
    ForceNode node,
    bool isFocusMode,
  ) {
    final accent = GraphPalette.nodeAccent(view, libraryColors);
    final highlighted =
        selectedNodeId == null || view.id == selectedNodeId ||
        highlightedNodeIds.contains(view.id);
    final dimmed = isFocusMode && !highlighted;
    final isSelected = view.id == selectedNodeId;
    final radius = node.radius + (isSelected ? 2.5 : 0);

    final center = Offset(node.x, node.y);

    // 阴影
    canvas.drawCircle(
      center.translate(0, 3),
      radius,
      Paint()
        ..color = accent.withValues(alpha: dimmed ? 0.06 : 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final fill = Paint()
      ..color = GraphPalette.nodeFill(accent).withValues(alpha: dimmed ? 0.4 : 1);
    canvas.drawCircle(center, radius, fill);

    // 共享实体：外圈用第二种来源色，明确表达「跨库同一实体」。
    final ringColor = dimmed ? accent.withValues(alpha: 0.25) : accent;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.6 : 1.8,
    );
    if (view.isShared) {
      final second = GraphPalette.sharedAccent(view, libraryColors);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 3.4),
        -math.pi / 2,
        math.pi,
        false,
        Paint()
          ..color = dimmed ? second.withValues(alpha: 0.25) : second
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }

    if (isSelected) {
      canvas.drawCircle(
        center,
        radius + 7,
        Paint()
          ..color = accent.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // 缩略视图里隐藏文字，避免节点变成一团重叠的标签。
    if (scale >= GraphPalette.labelVisibilityScale || isSelected) {
      _paintNodeLabel(canvas, view, center, radius, accent, dimmed);
    }
  }

  void _paintNodeLabel(
    Canvas canvas,
    GraphViewNode view,
    Offset center,
    double radius,
    Color accent,
    bool dimmed,
  ) {
    final fontSize = GraphPalette.nodeLabelSize(view);
    final label = GraphPalette.nodeLabel(
      view,
      maxLength: radius > 32 ? 8 : 6,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.15,
          color: Color.lerp(
            accent,
            const Color(0xFF0F172A),
            0.32,
          )!.withValues(alpha: dimmed ? 0.35 : 1),
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: radius * 1.75);

    painter.paint(
      canvas,
      Offset(
        center.dx - painter.width / 2,
        center.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) {
    return oldDelegate.scale != scale ||
        oldDelegate.translate != translate ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.draggingNodeId != draggingNodeId ||
        oldDelegate.nodes != nodes ||
        oldDelegate.data != data ||
        oldDelegate.highlightedNodeIds.length != highlightedNodeIds.length;
  }
}
