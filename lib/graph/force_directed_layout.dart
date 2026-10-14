import 'dart:math' as math;
import 'dart:ui' show Offset;

// ========== 力导向布局 ==========
// 纯 Dart 实现，无 Flutter 渲染依赖，便于单测。
// 特点：
//   · 网格加速的斥力计算，避免 O(n²) 在大图谱上卡顿。
//   · 弹簧引力 + 中心重力 + 同源聚类引力，密集知识点自然成簇。
//   · 支持钉住节点（用户拖动后保持）与热启动（刷新时保留已有位置）。
//   · 完全确定性：初始位置用黄金角螺旋，不使用随机数。

class ForceNode {
  ForceNode({
    required this.id,
    required this.x,
    required this.y,
    this.pinned = false,
    this.mass = 1,
    this.clusterId,
    this.radius = 24,
  });

  final int id;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  bool pinned;
  double mass;

  /// 来源知识库（用于聚类引力与配色），可为空。
  int? clusterId;

  /// 节点半径，参与碰撞消解。
  double radius;

  Offset get position => Offset(x, y);
}

class ForceEdge {
  const ForceEdge({
    required this.source,
    required this.target,
    this.weight = 1,
  });

  final int source;
  final int target;
  final double weight;
}

class ForceLayoutConfig {
  const ForceLayoutConfig({
    this.iterations = 220,
    this.idealEdgeLength = 118,
    this.repulsion = 20000,
    this.springStrength = 0.05,
    this.gravity = 0.014,
    this.clusterGravity = 0.032,
    this.damping = 0.86,
    this.maxDisplacement = 42,
    this.repulsionCutoff = 260,
    this.minDistance = 22,
    this.padding = 44,
    this.collisionPasses = 2,
  });

  final int iterations;
  final double idealEdgeLength;
  final double repulsion;
  final double springStrength;
  final double gravity;
  final double clusterGravity;
  final double damping;
  final double maxDisplacement;
  final double repulsionCutoff;
  final double minDistance;
  final double padding;
  final int collisionPasses;

  ForceLayoutConfig copyWith({
    int? iterations,
    double? idealEdgeLength,
    double? repulsion,
    double? springStrength,
    double? gravity,
    double? clusterGravity,
    double? damping,
    double? maxDisplacement,
    double? repulsionCutoff,
    double? minDistance,
    double? padding,
    int? collisionPasses,
  }) {
    return ForceLayoutConfig(
      iterations: iterations ?? this.iterations,
      idealEdgeLength: idealEdgeLength ?? this.idealEdgeLength,
      repulsion: repulsion ?? this.repulsion,
      springStrength: springStrength ?? this.springStrength,
      gravity: gravity ?? this.gravity,
      clusterGravity: clusterGravity ?? this.clusterGravity,
      damping: damping ?? this.damping,
      maxDisplacement: maxDisplacement ?? this.maxDisplacement,
      repulsionCutoff: repulsionCutoff ?? this.repulsionCutoff,
      minDistance: minDistance ?? this.minDistance,
      padding: padding ?? this.padding,
      collisionPasses: collisionPasses ?? this.collisionPasses,
    );
  }
}

class ForceDirectedLayout {
  const ForceDirectedLayout({this.config = const ForceLayoutConfig()});

  final ForceLayoutConfig config;

  /// 把节点按黄金角螺旋铺开，保证初始布局稳定且无重叠。
  static void seedPositions({
    required List<ForceNode> nodes,
    required double width,
    required double height,
    double padding = 56,
  }) {
    if (nodes.isEmpty) return;
    final centerX = width / 2;
    final centerY = height / 2;
    final usable = math.min(
      math.max(1, width - padding * 2),
      math.max(1, height - padding * 2),
    );
    final goldenAngle = math.pi * (3 - math.sqrt(5));
    final spacing = math.max(
      30.0,
      usable / (2 * math.sqrt(nodes.length.toDouble())),
    );
    for (var index = 0; index < nodes.length; index++) {
      final radius = spacing * math.sqrt(index + 0.5);
      final angle = goldenAngle * index;
      nodes[index]
        ..x = centerX + radius * math.cos(angle)
        ..y = centerY + radius * math.sin(angle)
        ..vx = 0
        ..vy = 0;
    }
  }

  /// 运行布局。会直接修改 [nodes] 的坐标。
  ///
  /// [width]/[height] 是画布可用尺寸；结果会收敛到该范围内。
  void run({
    required List<ForceNode> nodes,
    required List<ForceEdge> edges,
    required double width,
    required double height,
  }) {
    if (nodes.isEmpty) return;
    final safeWidth = math.max(1.0, width);
    final safeHeight = math.max(1.0, height);
    final center = Offset(safeWidth / 2, safeHeight / 2);
    final nodeById = {for (final node in nodes) node.id: node};
    final resolvedEdges = <(ForceNode, ForceNode, double)>[];
    for (final edge in edges) {
      final source = nodeById[edge.source];
      final target = nodeById[edge.target];
      if (source == null || target == null || source == target) continue;
      resolvedEdges.add((source, target, edge.weight));
    }

    final clusters = <int?, List<ForceNode>>{};
    for (final node in nodes) {
      clusters.putIfAbsent(node.clusterId, () => <ForceNode>[]).add(node);
    }

    final iterations = config.iterations;
    for (var iteration = 0; iteration < iterations; iteration++) {
      final alpha = _temperature(iteration, iterations);
      _applyRepulsion(nodes);
      _applySprings(resolvedEdges);
      _applyGravity(nodes, center);
      _applyClusterGravity(clusters, center);
      _integrate(nodes, alpha, center, safeWidth, safeHeight);
    }

    _resolveCollisions(nodes, safeWidth, safeHeight);
    _clampToBounds(nodes, safeWidth, safeHeight);
  }

  /// 温度曲线：前 15% 保持高温让节点铺开，之后指数冷却收敛。
  double _temperature(int iteration, int total) {
    final progress = total <= 0 ? 1.0 : iteration / total;
    if (progress < 0.15) return 1.0;
    final remaining = (progress - 0.15) / 0.85;
    return math.exp(-3.2 * remaining);
  }

  void _applyRepulsion(List<ForceNode> nodes) {
    for (final node in nodes) {
      node.vx = 0;
      node.vy = 0;
    }
    final grid = _SpatialGrid(
      cellSize: config.repulsionCutoff,
      nodes: nodes,
    );
    final cutoffSquared = config.repulsionCutoff * config.repulsionCutoff;
    final minDistanceSquared = config.minDistance * config.minDistance;

    for (final node in nodes) {
      final neighbors = grid.neighborsOf(node);
      for (final other in neighbors) {
        if (identical(other, node)) continue;
        final dx = node.x - other.x;
        final dy = node.y - other.y;
        var distanceSquared = dx * dx + dy * dy;
        if (distanceSquared > cutoffSquared) continue;
        if (distanceSquared < minDistanceSquared) {
          distanceSquared = minDistanceSquared;
        }
        final distance = math.sqrt(distanceSquared);
        final force =
            config.repulsion * other.mass / distanceSquared;
        final ux = dx / distance;
        final uy = dy / distance;
        node.vx += ux * force;
        node.vy += uy * force;
      }
    }
  }

  void _applySprings(List<(ForceNode, ForceNode, double)> edges) {
    for (final (source, target, weight) in edges) {
      final dx = target.x - source.x;
      final dy = target.y - source.y;
      final distance = math.max(config.minDistance, math.sqrt(dx * dx + dy * dy));
      final displacement = distance - config.idealEdgeLength;
      final force = displacement * config.springStrength * weight;
      final ux = dx / distance;
      final uy = dy / distance;
      source.vx += ux * force;
      source.vy += uy * force;
      target.vx -= ux * force;
      target.vy -= uy * force;
    }
  }

  void _applyGravity(List<ForceNode> nodes, Offset center) {
    for (final node in nodes) {
      node.vx += (center.dx - node.x) * config.gravity;
      node.vy += (center.dy - node.y) * config.gravity;
    }
  }

  void _applyClusterGravity(
    Map<int?, List<ForceNode>> clusters,
    Offset center,
  ) {
    for (final entry in clusters.entries) {
      final members = entry.value;
      if (members.length < 2 || entry.key == null) continue;
      var sumX = 0.0;
      var sumY = 0.0;
      for (final node in members) {
        sumX += node.x;
        sumY += node.y;
      }
      final centroidX = sumX / members.length;
      final centroidY = sumY / members.length;
      // 聚类引力温和地把同源节点聚拢，同时仍受中心重力约束。
      final pullX = (centroidX - center.dx) * 0.35;
      final pullY = (centroidY - center.dy) * 0.35;
      for (final node in members) {
        node.vx += (centroidX - pullX - node.x) * config.clusterGravity;
        node.vy += (centroidY - pullY - node.y) * config.clusterGravity;
      }
    }
  }

  void _integrate(
    List<ForceNode> nodes,
    double alpha,
    Offset center,
    double width,
    double height,
  ) {
    for (final node in nodes) {
      if (node.pinned) {
        node.vx = 0;
        node.vy = 0;
        continue;
      }
      node.vx *= config.damping;
      node.vy *= config.damping;
      final magnitude = math.sqrt(node.vx * node.vx + node.vy * node.vy);
      if (magnitude <= 1e-6) continue;
      final limit = config.maxDisplacement * alpha;
      final step = math.min(magnitude, limit);
      node.x += node.vx / magnitude * step;
      node.y += node.vy / magnitude * step;
    }
  }

  /// 简单的圆-圆碰撞消解，避免节点严重重叠遮挡标签。
  void _resolveCollisions(
    List<ForceNode> nodes,
    double width,
    double height,
  ) {
    for (var pass = 0; pass < config.collisionPasses; pass++) {
      final grid = _SpatialGrid(
        cellSize: config.minDistance * 3,
        nodes: nodes,
      );
      var moved = false;
      for (final node in nodes) {
        for (final other in grid.neighborsOf(node)) {
          if (identical(other, node)) continue;
          final dx = other.x - node.x;
          final dy = other.y - node.y;
          var distance = math.sqrt(dx * dx + dy * dy);
          final minGap = node.radius + other.radius + 6;
          if (distance >= minGap) continue;
          if (distance < 1e-3) {
            distance = 1e-3;
          }
          final overlap = (minGap - distance) / 2;
          final ux = dx / distance;
          final uy = dy / distance;
          if (!node.pinned) {
            node.x -= ux * overlap;
            node.y -= uy * overlap;
          }
          if (!other.pinned) {
            other.x += ux * overlap;
            other.y += uy * overlap;
          }
          moved = true;
        }
      }
      if (!moved) break;
    }
  }

  void _clampToBounds(
    List<ForceNode> nodes,
    double width,
    double height,
  ) {
    final padding = config.padding;
    for (final node in nodes) {
      final minX = padding + node.radius;
      final maxX = math.max(minX, width - padding - node.radius);
      final minY = padding + node.radius;
      final maxY = math.max(minY, height - padding - node.radius);
      node.x = node.x.clamp(minX, maxX);
      node.y = node.y.clamp(minY, maxY);
    }
  }
}

/// 均匀网格空间索引，只返回 3×3 邻域内的节点，把斥力计算降到近似线性。
class _SpatialGrid {
  _SpatialGrid({required this.cellSize, required List<ForceNode> nodes})
    : _cells = <int, List<ForceNode>>{} {
    for (final node in nodes) {
      final key = _key(_cellX(node.x), _cellY(node.y));
      _cells.putIfAbsent(key, () => <ForceNode>[]).add(node);
    }
  }

  final double cellSize;
  final Map<int, List<ForceNode>> _cells;

  int _cellX(double x) => (x / cellSize).floor();
  int _cellY(double y) => (y / cellSize).floor();

  int _key(int cx, int cy) => cx * 73856093 ^ cy * 19349663;

  Iterable<ForceNode> neighborsOf(ForceNode node) sync* {
    final cx = _cellX(node.x);
    final cy = _cellY(node.y);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final bucket = _cells[_key(cx + dx, cy + dy)];
        if (bucket == null) continue;
        yield* bucket;
      }
    }
  }
}
