import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../database/models/graph_records.dart';
import '../database/models/knowledge_library_record.dart';
import 'graph_vocabulary.dart';

// ========== 图谱视觉规范 ==========
// 颜色优先取自知识库自身的封面主题色，不按名称硬编码学科。
// 关系用线条颜色 + 实虚线 + 箭头方向表达语义，不使用装饰性特效。

class GraphPalette {
  const GraphPalette._();

  /// 知识库没有主题色时的回退序列（柔和蓝 / 绿 / 紫 / 橙 / 青）。
  static const List<Color> fallbackLibraryColors = <Color>[
    Color(0xFF5B90FF),
    Color(0xFF62BBA0),
    Color(0xFFA58CE5),
    Color(0xFFF0BC5C),
    Color(0xFF5EC5D8),
    Color(0xFFF29BB0),
  ];

  /// 关系配色。与 `GraphRelationTypes` 一一对应。
  static const Map<String, Color> _relationColors = <String, Color>{
    GraphRelationTypes.prerequisite: Color(0xFF2563EB),
    GraphRelationTypes.dependsOn: Color(0xFF3B82F6),
    GraphRelationTypes.belongsTo: Color(0xFF7C3AED),
    GraphRelationTypes.contains: Color(0xFF8B5CF6),
    GraphRelationTypes.appliedTo: Color(0xFF059669),
    GraphRelationTypes.extends_: Color(0xFFF59E0B),
    GraphRelationTypes.related: Color(0xFF94A3B8),
  };

  static Color relationColor(String relationType) {
    final normalized = GraphRelationTypes.normalize(relationType);
    return _relationColors[normalized] ?? _relationColors[GraphRelationTypes.related]!;
  }

  static bool relationDashed(String relationType) =>
      GraphRelationTypes.specFor(relationType).dashed;

  static bool relationDirected(String relationType) =>
      GraphRelationTypes.specFor(relationType).directed;

  /// 按知识库 ID 稳定分配回退色，保证同一本库颜色一致。
  static Color fallbackColorFor(int libraryId) =>
      fallbackLibraryColors[libraryId.abs() % fallbackLibraryColors.length];

  /// 按顺序取一个与其他知识库不同的主题色。
  /// 超出预置色板时按黄金角旋转色相，保证任意本数都能区分。
  static Color libraryColorForIndex(int index) {
    if (index >= 0 && index < fallbackLibraryColors.length) {
      return fallbackLibraryColors[index];
    }
    final hue = (index * 137.508) % 360;
    return HSLColor.fromAHSL(1, hue, 0.52, 0.60).toColor();
  }

  /// 为每本知识库分配一个颜色，保证不同知识库在图谱上可区分。
  ///
  /// 规则：优先使用知识库自己的封面主题色；当多本知识库共用同一个默认色
  /// （或封面色与已用颜色重复）时，按 id 顺序分配互不相同的柔和主题色。
  /// 结果只依赖知识库 id，切换选择或刷新都不会变色。
  static Map<int, Color> assignLibraryColors(
    List<KnowledgeLibraryRecord> libraries,
  ) {
    final ordered = libraries.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    final result = <int, Color>{};
    final used = <Color>{};
    var paletteCursor = 0;

    for (final library in ordered) {
      var color = library.coverColor == 0 ? null : Color(library.coverColor);
      if (color != null && used.contains(color)) {
        color = null;
      }
      if (color == null) {
        while (used.contains(libraryColorForIndex(paletteCursor))) {
          paletteCursor++;
        }
        color = libraryColorForIndex(paletteCursor);
        paletteCursor++;
      }
      used.add(color);
      result[library.id] = color;
    }
    return result;
  }

  /// 节点描边色：优先用来源知识库的封面主题色。
  static Color nodeAccent(GraphViewNode node, Map<int, Color> libraryColors) {
    if (node.primaryLibraryId != null) {
      final color = libraryColors[node.primaryLibraryId];
      if (color != null) return color;
    }
    return const Color(0xFF5B90FF);
  }

  /// 节点填充色：主题色的极浅版本，保持画布清爽。
  static Color nodeFill(Color accent) =>
      Color.lerp(accent, Colors.white, 0.84)!;

  /// 共享实体（属于多本知识库）的第二强调色。
  static Color sharedAccent(GraphViewNode node, Map<int, Color> libraryColors) {
    if (node.libraryIds.length < 2) {
      return nodeAccent(node, libraryColors);
    }
    final second = node.libraryIds[1];
    return libraryColors[second] ?? fallbackColorFor(second);
  }

  /// 节点半径：按连接数适度放大，并限制上限避免遮挡。
  /// 手机屏幕上单节点直径控制在 40–72 逻辑像素，保证多节点时仍能分辨。
  static double nodeRadius(GraphViewNode node) {
    final base = node.isShared ? 25.0 : 22.0;
    final growth = math.min(node.degree, 8) * 1.7;
    return (base + growth).clamp(20.0, 36.0);
  }

  /// 节点标签字号。
  static double nodeLabelSize(GraphViewNode node) {
    final label = node.label;
    if (label.length <= 4) return 12;
    if (label.length <= 7) return 11;
    return 10;
  }

  /// 低于该缩放比例时隐藏节点文字，避免缩略视图变成一团文字。
  static const double labelVisibilityScale = 0.55;

  /// 节点标签最多显示字数，超出省略，避免线条穿过大量文字。
  static String nodeLabel(GraphViewNode node, {int maxLength = 8}) {
    final label = node.label;
    if (label.length <= maxLength) return label;
    return '${label.substring(0, maxLength)}…';
  }
}

/// 关系标签的中文说明，用于详情面板。
String graphRelationExplanation(String relationType) {
  switch (GraphRelationTypes.normalize(relationType)) {
    case GraphRelationTypes.prerequisite:
      return '起点是终点的前置知识。终点掌握不稳时，优先回到起点补基础。';
    case GraphRelationTypes.dependsOn:
      return '终点依赖起点成立。起点有缺口时，终点也容易出错。';
    case GraphRelationTypes.belongsTo:
      return '起点从属于终点所在的分类体系，可从上位概念进入分支细节。';
    case GraphRelationTypes.contains:
      return '起点包含终点，属于层级归属关系。';
    case GraphRelationTypes.appliedTo:
      return '起点被应用到终点所在的场景中，是典型的跨知识库连接。';
    case GraphRelationTypes.extends_:
      return '终点是起点的延伸扩展，属于进阶方向。';
    default:
      return '两个知识点在当前资料中存在学习关联，适合同一次复习时一起理解。';
  }
}
