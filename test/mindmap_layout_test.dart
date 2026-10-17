import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/ui/widgets/mindmap_layout.dart';

void main() {
  test('nested Markdown bullets retain real parent-child relationships', () {
    final entries = parseMindmap(
      '主题\n- 概念\n  - 定义\n    - 条件\n  - 公式\n- 方法\n  - 步骤',
    );
    expect(entries.map((entry) => entry.parent), [null, 0, 1, 2, 1, 0, 5]);
    expect(entries.map((entry) => entry.title), [
      '主题',
      '概念',
      '定义',
      '条件',
      '公式',
      '方法',
      '步骤',
    ]);
  });

  test('heading outlines and saved Mermaid indentation remain readable', () {
    final markdown = parseMindmap('# 主题\n## 概念\n- 定义\n  - 条件\n## 方法\n- 步骤');
    expect(markdown.map((entry) => entry.parent), [null, 0, 1, 2, 0, 4]);
    final mermaid = parseMindmap(
      '```mermaid\nmindmap\n  root((主题))\n    概念\n      定义\n    方法\n      步骤\n```',
    );
    expect(mermaid.map((entry) => entry.parent), [null, 0, 1, 0, 3]);
    expect(mermaid.first.title, '主题');
  });

  test(
    'bilateral branches never overlap with unequal node sizes and retain their color family',
    () {
      final entries = parseMindmap(
        '主题\n- 概念\n  - 长说明\n  - 公式\n- 方法\n  - 步骤\n- 例子\n  - 条件',
      );
      final layout = MindmapLayout(
        entries: entries,
        nodeSizes: {
          for (final entry in entries)
            entry.id: Size(
              entry.id.isEven ? 208 : 160,
              entry.id == 2
                  ? 260
                  : entry.id == 5
                  ? 140
                  : 52,
            ),
        },
      );
      final root = layout.bounds[0]!;
      expect(
        layout.bounds.values.any((rect) => rect.right < root.left),
        isTrue,
      );
      expect(
        layout.bounds.values.any((rect) => rect.left > root.right),
        isTrue,
      );
      expect(layout.branches[2], layout.branches[1]);
      expect(layout.branches[7], layout.branches[6]);
      expect(layout.branches[1], isNot(layout.branches[4]));
      final bounds = layout.bounds.values.toList();
      for (var i = 0; i < bounds.length; i++) {
        expect(bounds[i].left, greaterThanOrEqualTo(0));
        expect(bounds[i].bottom, lessThanOrEqualTo(layout.size.height));
        for (var j = i + 1; j < bounds.length; j++) {
          expect(
            bounds[i].overlaps(bounds[j]),
            isFalse,
            reason: 'nodes $i and $j overlap',
          );
        }
      }
      final collapsed = MindmapLayout(
        entries: entries,
        nodeSizes: {for (final entry in entries) entry.id: const Size(160, 52)},
        collapsed: {1},
      );
      expect(collapsed.bounds.keys, isNot(contains(2)));
      expect(collapsed.bounds.keys, isNot(contains(3)));
      expect(collapsed.bounds.keys, containsAll([0, 1, 4, 5, 6, 7]));
    },
  );
}
