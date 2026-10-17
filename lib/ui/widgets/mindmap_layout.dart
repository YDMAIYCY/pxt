import 'dart:math' as math;

import 'package:flutter/painting.dart';

class MindmapEntry {
  const MindmapEntry(this.id, this.title, this.parent);
  final int id;
  final String title;
  final int? parent;
}

List<MindmapEntry> parseMindmap(String text) {
  final entries = <MindmapEntry>[];
  final stack = <({int depth, int id})>[];
  int headingDepth = 0;
  int? plainIndent;
  int? rootListIndent;
  for (final line in text.split('\n')) {
    final raw = line.replaceAll('\t', '  ');
    var title = raw.trim();
    if (title.isEmpty ||
        title.startsWith('```') ||
        title == 'mindmap' ||
        title.startsWith('graph ') ||
        title.startsWith('flowchart ')) {
      continue;
    }
    final indent = (raw.length - raw.trimLeft().length) ~/ 2;
    final heading = RegExp(r'^(#+)\s+').firstMatch(title);
    final bullet = RegExp(r'^[-*+]\s+').hasMatch(title);
    int depth;
    if (entries.isEmpty) {
      depth = 0;
      if (bullet) rootListIndent = indent;
    } else if (heading != null) {
      depth = math.max(1, heading.group(1)!.length - 1);
      headingDepth = depth;
    } else if (bullet) {
      depth = rootListIndent == null
          ? headingDepth + indent + 1
          : math.max(1, indent - rootListIndent);
    } else {
      plainIndent ??= indent;
      depth = headingDepth + math.max(0, indent - plainIndent).toInt() + 1;
    }
    title = title.replaceFirst(RegExp(r'^(#+\s+|[-*+]\s+|[├└│─]+\s*)'), '');
    final root = RegExp(r'^root\(\((.*)\)\)$').firstMatch(title);
    if (root != null) title = root.group(1)!;
    if (title.isEmpty) continue;
    while (stack.isNotEmpty && stack.last.depth >= depth) {
      stack.removeLast();
    }
    final id = entries.length;
    entries.add(MindmapEntry(id, title, stack.lastOrNull?.id));
    stack.add((depth: depth, id: id));
  }
  return entries;
}

class MindmapLayout {
  MindmapLayout({
    required this.entries,
    required Map<int, Size> nodeSizes,
    Set<int> collapsed = const {},
  }) {
    for (final entry in entries) {
      if (entry.parent != null) {
        _children.putIfAbsent(entry.parent!, () => []).add(entry.id);
      }
    }
    if (entries.isEmpty) {
      size = Size.zero;
      return;
    }
    final root = entries.first.id;
    final spans = <int, double>{};
    double span(int id) => spans.putIfAbsent(id, () {
      final children = collapsed.contains(id) ? <int>[] : _children[id] ?? [];
      return math.max(
        nodeSizes[id]!.height,
        children.fold(0.0, (sum, child) => sum + span(child)) +
            math.max(0, children.length - 1) * 32,
      );
    });
    span(root);
    final rootSize = nodeSizes[root]!;
    bounds[root] = Rect.fromCenter(
      center: Offset.zero,
      width: rootSize.width,
      height: rootSize.height,
    );
    branches[root] = -1;
    final left = <int>[], right = <int>[];
    double leftHeight = 0, rightHeight = 0;
    if (!collapsed.contains(root)) {
      for (final id in _children[root] ?? <int>[]) {
        if (rightHeight <= leftHeight) {
          right.add(id);
          rightHeight += span(id) + 32;
        } else {
          left.add(id);
          leftHeight += span(id) + 32;
        }
      }
    }
    void placeChildren(
      int parent,
      List<int> children,
      bool onRight,
      int branch,
    ) {
      if (children.isEmpty) return;
      final parentRect = bounds[parent]!;
      final total =
          children.fold(0.0, (sum, id) => sum + span(id)) +
          (children.length - 1) * 32;
      var y = parentRect.center.dy - total / 2;
      for (final id in children) {
        final nodeSize = nodeSizes[id]!;
        final x = onRight
            ? parentRect.right + 88
            : parentRect.left - 88 - nodeSize.width;
        bounds[id] = Rect.fromLTWH(
          x,
          y + (span(id) - nodeSize.height) / 2,
          nodeSize.width,
          nodeSize.height,
        );
        branches[id] = parent == root ? (_children[root]!.indexOf(id)) : branch;
        rightSide[id] = onRight;
        if (!collapsed.contains(id)) {
          placeChildren(id, _children[id] ?? [], onRight, branches[id]!);
        }
        y += span(id) + 32;
      }
    }

    placeChildren(root, right, true, -1);
    placeChildren(root, left, false, -1);
    final area = bounds.values.reduce((a, b) => a.expandToInclude(b));
    final offset = Offset(48 - area.left, 48 - area.top);
    bounds.updateAll((_, rect) => rect.shift(offset));
    size = Size(area.width + 96, area.height + 96);
  }

  final List<MindmapEntry> entries;
  final Map<int, List<int>> _children = {};
  final Map<int, Rect> bounds = {};
  final Map<int, int> branches = {};
  final Map<int, bool> rightSide = {};
  late final Size size;
  bool hasChildren(int id) => _children[id]?.isNotEmpty == true;
}
