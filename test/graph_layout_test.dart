import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/graph/force_directed_layout.dart';

void main() {
  List<ForceNode> buildNodes(int count) => List<ForceNode>.generate(
    count,
    (index) => ForceNode(
      id: index,
      x: 0,
      y: 0,
      radius: 26,
      clusterId: index % 2,
    ),
  );

  List<ForceEdge> buildChain(int count) => List<ForceEdge>.generate(
    math.max(0, count - 1),
    (index) => ForceEdge(source: index, target: index + 1),
  );

  group('ForceDirectedLayout', () {
    test('黄金角螺旋初始位置确定且互不重合', () {
      final nodes = buildNodes(40);
      ForceDirectedLayout.seedPositions(
        nodes: nodes,
        width: 800,
        height: 900,
      );

      final first = nodes.first;
      final second = ForceDirectedLayout();
      final repeat = buildNodes(40);
      ForceDirectedLayout.seedPositions(
        nodes: repeat,
        width: 800,
        height: 900,
      );

      expect(repeat.first.x, first.x);
      expect(repeat.first.y, first.y);

      final positions = nodes.map((n) => '${n.x.toStringAsFixed(3)},${n.y.toStringAsFixed(3)}').toSet();
      expect(positions.length, nodes.length);
      expect(second.config.iterations, greaterThan(0));
    });

    test('布局结果有限、落在画布范围内、无 NaN', () {
      final nodes = buildNodes(80);
      ForceDirectedLayout.seedPositions(
        nodes: nodes,
        width: 900,
        height: 1000,
      );
      const layout = ForceDirectedLayout();
      layout.run(
        nodes: nodes,
        edges: buildChain(80),
        width: 900,
        height: 1000,
      );

      for (final node in nodes) {
        expect(node.x.isFinite, isTrue, reason: 'node ${node.id} x 不是有限数');
        expect(node.y.isFinite, isTrue, reason: 'node ${node.id} y 不是有限数');
        expect(node.x, greaterThanOrEqualTo(0));
        expect(node.y, greaterThanOrEqualTo(0));
        expect(node.x, lessThanOrEqualTo(900));
        expect(node.y, lessThanOrEqualTo(1000));
      }
    });

    test('同一输入重复求解得到完全相同的坐标（确定性）', () {
      List<OffsetLike> solve() {
        final nodes = buildNodes(50);
        ForceDirectedLayout.seedPositions(
          nodes: nodes,
          width: 700,
          height: 800,
        );
        const ForceDirectedLayout().run(
          nodes: nodes,
          edges: buildChain(50),
          width: 700,
          height: 800,
        );
        return nodes
            .map((n) => OffsetLike(n.x, n.y))
            .toList(growable: false);
      }

      final a = solve();
      final b = solve();
      for (var index = 0; index < a.length; index++) {
        expect(a[index].x, b[index].x);
        expect(a[index].y, b[index].y);
      }
    });

    test('相连节点比无关联节点更靠近', () {
      final nodes = buildNodes(30);
      ForceDirectedLayout.seedPositions(
        nodes: nodes,
        width: 900,
        height: 900,
      );
      // 只把 0-1-2 连成一条链，其余孤立。
      const ForceDirectedLayout().run(
        nodes: nodes,
        edges: const [
          ForceEdge(source: 0, target: 1, weight: 1.4),
          ForceEdge(source: 1, target: 2, weight: 1.4),
        ],
        width: 900,
        height: 900,
      );

      double distance(int a, int b) {
        final dx = nodes[a].x - nodes[b].x;
        final dy = nodes[a].y - nodes[b].y;
        return math.sqrt(dx * dx + dy * dy);
      }

      final linkedAverage = (distance(0, 1) + distance(1, 2)) / 2;
      final unlinkedAverage = (distance(0, 20) + distance(1, 25)) / 2;
      expect(linkedAverage, lessThan(unlinkedAverage));
    });

    test('钉住的节点在布局中不被移动', () {
      final nodes = buildNodes(20);
      ForceDirectedLayout.seedPositions(
        nodes: nodes,
        width: 600,
        height: 600,
      );
      nodes[3]
        ..pinned = true
        ..x = 123
        ..y = 456;

      const ForceDirectedLayout().run(
        nodes: nodes,
        edges: buildChain(20),
        width: 600,
        height: 600,
      );

      expect(nodes[3].x, 123);
      expect(nodes[3].y, 456);
    });

    test('节点不会严重重叠（碰撞消解后间距达标）', () {
      final nodes = buildNodes(60);
      ForceDirectedLayout.seedPositions(
        nodes: nodes,
        width: 800,
        height: 800,
      );
      const ForceDirectedLayout().run(
        nodes: nodes,
        edges: buildChain(60),
        width: 800,
        height: 800,
      );

      var severeOverlaps = 0;
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          final dx = nodes[i].x - nodes[j].x;
          final dy = nodes[i].y - nodes[j].y;
          final distance = math.sqrt(dx * dx + dy * dy);
          if (distance < (nodes[i].radius + nodes[j].radius) * 0.4) {
            severeOverlaps++;
          }
        }
      }
      expect(severeOverlaps, 0);
    });

    test('空输入不会抛异常', () {
      const ForceDirectedLayout().run(
        nodes: <ForceNode>[],
        edges: const <ForceEdge>[],
        width: 100,
        height: 100,
      );
      expect(true, isTrue);
    });

    test('600 节点规模可在合理时间内求解', () {
      final nodes = buildNodes(600);
      ForceDirectedLayout.seedPositions(
        nodes: nodes,
        width: 1600,
        height: 1800,
      );
      final edges = List<ForceEdge>.generate(
        900,
        (index) => ForceEdge(source: index % 600, target: (index * 7 + 3) % 600),
      );
      final stopwatch = Stopwatch()..start();
      const ForceDirectedLayout().run(
        nodes: nodes,
        edges: edges,
        width: 1600,
        height: 1800,
      );
      stopwatch.stop();
      // 手机端可接受的上限；桌面测试环境通常远低于此。
      expect(stopwatch.elapsedMilliseconds, lessThan(4000));
    });
  });
}

class OffsetLike {
  const OffsetLike(this.x, this.y);
  final double x;
  final double y;
}
