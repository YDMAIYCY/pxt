import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/models/graph_records.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/graph/graph_style.dart';

// ========== 知识库配色测试 ==========
// 不同知识库必须拿到不同的颜色；颜色只依赖知识库 id，切换选择不会变色。

void main() {
  KnowledgeLibraryRecord library({
    required int id,
    required String name,
    int coverColor = 0xFF5B90FF,
  }) => KnowledgeLibraryRecord(
    id: id,
    userId: 1,
    name: name,
    createdAt: DateTime(2026, 10, 1),
    updatedAt: DateTime(2026, 10, 1),
    coverColor: coverColor,
  );

  group('assignLibraryColors', () {
    test('多本知识库共用默认封面蓝时仍然分到不同颜色', () {
      final colors = GraphPalette.assignLibraryColors([
        library(id: 13, name: '功能数据库'),
        library(id: 14, name: '学习资料知识库'),
        library(id: 15, name: '英语语法'),
      ]);

      expect(colors, hasLength(3));
      expect(
        colors.values.toSet(),
        hasLength(3),
        reason: '不同知识库不能共用同一个颜色',
      );
      expect(colors[13], GraphPalette.fallbackLibraryColors[0]);
      expect(colors[14], GraphPalette.fallbackLibraryColors[1]);
      expect(colors[15], GraphPalette.fallbackLibraryColors[2]);
    });

    test('知识库自带的不同封面主题色被优先采用', () {
      final colors = GraphPalette.assignLibraryColors([
        library(id: 1, name: '数学', coverColor: 0xFF5B90FF),
        library(id: 2, name: '英语', coverColor: 0xFFA58CE5),
        library(id: 3, name: '机器学习', coverColor: 0xFF62BBA0),
      ]);
      expect(colors[1], const Color(0xFF5B90FF));
      expect(colors[2], const Color(0xFFA58CE5));
      expect(colors[3], const Color(0xFF62BBA0));
    });

    test('封面色与已用颜色冲突时改用调色板，不出现重复', () {
      final colors = GraphPalette.assignLibraryColors([
        library(id: 1, name: 'A', coverColor: 0xFFA58CE5),
        library(id: 2, name: 'B', coverColor: 0xFFA58CE5),
      ]);
      expect(colors[1], const Color(0xFFA58CE5));
      expect(colors[2], isNot(const Color(0xFFA58CE5)));
      expect(colors.values.toSet(), hasLength(2));
    });

    test('颜色只依赖知识库 id，与传入顺序无关', () {
      final a = GraphPalette.assignLibraryColors([
        library(id: 13, name: '功能数据库'),
        library(id: 14, name: '学习资料知识库'),
      ]);
      final b = GraphPalette.assignLibraryColors([
        library(id: 14, name: '学习资料知识库'),
        library(id: 13, name: '功能数据库'),
      ]);
      expect(a, b);
    });

    test('超过预置色板本数时仍能区分', () {
      final libraries = List<KnowledgeLibraryRecord>.generate(
        10,
        (index) => library(id: index + 1, name: '库${index + 1}'),
      );
      final colors = GraphPalette.assignLibraryColors(libraries);
      expect(colors.values.toSet(), hasLength(10));
    });

    test('空列表不抛异常', () {
      expect(GraphPalette.assignLibraryColors(const []), isEmpty);
    });
  });

  group('节点配色', () {
    GraphViewNode node({
      required int id,
      required List<int> libraryIds,
    }) => GraphViewNode(
      id: id,
      label: '梯度',
      entityType: '概念',
      description: null,
      libraryIds: libraryIds,
      primaryLibraryId: libraryIds.isEmpty ? null : libraryIds.first,
      status: GraphNodeStatus.active,
      degree: 0,
      aliases: const [],
    );

    final colors = {
      1: const Color(0xFF5B90FF),
      2: const Color(0xFF62BBA0),
    };

    test('节点描边使用来源知识库的颜色', () {
      expect(
        GraphPalette.nodeAccent(node(id: 1, libraryIds: [1]), colors),
        const Color(0xFF5B90FF),
      );
      expect(
        GraphPalette.nodeAccent(node(id: 2, libraryIds: [2]), colors),
        const Color(0xFF62BBA0),
      );
    });

    test('跨库共享实体用第二个来源库的颜色作为第二强调色', () {
      final shared = node(id: 3, libraryIds: [1, 2]);
      expect(shared.isShared, isTrue);
      expect(
        GraphPalette.sharedAccent(shared, colors),
        const Color(0xFF62BBA0),
      );
    });

    test('没有来源颜色时回退到默认蓝', () {
      expect(
        GraphPalette.nodeAccent(node(id: 9, libraryIds: const []), colors),
        const Color(0xFF5B90FF),
      );
    });

    test('节点尺寸被限制在可触控范围内', () {
      final small = GraphViewNode(
        id: 1,
        label: 'A',
        entityType: '概念',
        description: null,
        libraryIds: const [1],
        primaryLibraryId: 1,
        status: GraphNodeStatus.active,
        degree: 0,
        aliases: const [],
      );
      final big = GraphViewNode(
        id: 2,
        label: 'B',
        entityType: '概念',
        description: null,
        libraryIds: const [1, 2],
        primaryLibraryId: 1,
        status: GraphNodeStatus.active,
        degree: 99,
        aliases: const [],
      );
      expect(GraphPalette.nodeRadius(small), greaterThanOrEqualTo(20));
      expect(GraphPalette.nodeRadius(big), lessThanOrEqualTo(36));
      expect(
        GraphPalette.nodeRadius(big),
        greaterThan(GraphPalette.nodeRadius(small)),
      );
    });

    test('长标签会被裁剪，避免线条穿过大量文字', () {
      final long = GraphViewNode(
        id: 1,
        label: '这是一个非常长的知识点名称',
        entityType: '概念',
        description: null,
        libraryIds: const [1],
        primaryLibraryId: 1,
        status: GraphNodeStatus.active,
        degree: 0,
        aliases: const [],
      );
      expect(GraphPalette.nodeLabel(long).length, lessThanOrEqualTo(9));
      expect(GraphPalette.nodeLabel(long), endsWith('…'));
    });
  });
}
