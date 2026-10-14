import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/graph/graph_vocabulary.dart';

void main() {
  group('GraphNameNormalizer', () {
    test('规范化会忽略大小写、空白与常见标点', () {
      expect(GraphNameNormalizer.normalize('  函数极限 '), '函数极限');
      expect(GraphNameNormalizer.normalize('Gradient'), 'gradient');
      expect(GraphNameNormalizer.normalize('梯度 向量'), '梯度向量');
      expect(GraphNameNormalizer.normalize('偏导数（一阶）'), '偏导数一阶');
      expect(GraphNameNormalizer.normalize('f(x)'), 'fx');
      expect(GraphNameNormalizer.normalize('   '), '');
    });

    test('保留数学语义符号，不误伤语义字符', () {
      expect(GraphNameNormalizer.normalize('x²+y²'), 'x²+y²');
      expect(GraphNameNormalizer.normalize('a≤b'), 'a≤b');
      expect(GraphNameNormalizer.normalize('∇f'), '∇f');
    });

    test('去重键包含实体类型，避免跨语义强行合并', () {
      final mathKey = GraphNameNormalizer.canonicalKey('函数', '概念');
      final codeKey = GraphNameNormalizer.canonicalKey('函数', '方法');
      expect(mathKey, isNot(codeKey));
      expect(mathKey, '函数|概念');
      expect(GraphNameNormalizer.canonicalKey('  ', '概念'), '');
    });

    test('同名同类型得到同一个键，大小写与空格不影响', () {
      expect(
        GraphNameNormalizer.canonicalKey('Gradient', '概念'),
        GraphNameNormalizer.canonicalKey(' gradient ', '概念'),
      );
    });
  });

  group('GraphRelationTypes', () {
    test('受控词表只包含约定的七种关系', () {
      expect(
        GraphRelationTypes.specs.map((spec) => spec.type).toSet(),
        {
          '前置知识',
          '属于',
          '包含',
          '应用于',
          '相关',
          '扩展',
          '依赖于',
        },
      );
    });

    test('模型自由文本被归一化到受控值', () {
      expect(GraphRelationTypes.normalize('prerequisite'), '前置知识');
      expect(GraphRelationTypes.normalize('前置'), '前置知识');
      expect(GraphRelationTypes.normalize('is_a'), '属于');
      expect(GraphRelationTypes.normalize('用于'), '应用于');
      expect(GraphRelationTypes.normalize('related_to'), '相关');
      expect(GraphRelationTypes.normalize('depends_on'), '依赖于');
      expect(GraphRelationTypes.normalize(''), '相关');
      expect(GraphRelationTypes.normalize('完全无法识别的东西'), '相关');
    });

    test('方向性：相关无方向，前置知识有方向', () {
      expect(GraphRelationTypes.specFor('相关').directed, isFalse);
      expect(GraphRelationTypes.specFor('related').dashed, isTrue);
      expect(GraphRelationTypes.specFor('前置知识').directed, isTrue);
      expect(GraphRelationTypes.specFor('前置知识').dashed, isFalse);
      expect(GraphRelationTypes.specFor('应用于').directed, isTrue);
    });
  });

  group('GraphEntityTypes', () {
    test('受控实体类型归一化', () {
      expect(GraphEntityTypes.normalize('定理'), '定理');
      expect(GraphEntityTypes.normalize('知识点'), '概念');
      expect(GraphEntityTypes.normalize('algorithm'), '算法');
      expect(GraphEntityTypes.normalize('公式'), '公式');
      expect(GraphEntityTypes.normalize('随便写的类型'), '概念');
      expect(GraphEntityTypes.normalize(null), '概念');
    });

    test('所有受控类型都能原样归一化', () {
      for (final type in GraphEntityTypes.all) {
        expect(GraphEntityTypes.normalize(type), type);
      }
    });
  });
}
