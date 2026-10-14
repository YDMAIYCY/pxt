import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/generator/graph_builder_service.dart';

void main() {
  group('parseExtractionResponse', () {
    test('解析实体与关系，并归一化类型', () {
      final draft = KnowledgeGraphBuilder.parseExtractionResponse({
        'entities': [
          {
            'name': '函数极限',
            'type': '概念',
            'description': '函数在趋近某点时的取值趋势',
            'aliases': ['limit'],
            'evidence': '当 x 趋近 a 时 f(x) 趋近 L',
            'confidence': 0.9,
          },
          {
            'name': '导数',
            'type': 'theorem',
            'aliases': 'derivative,微商',
          },
          {'name': ''},
        ],
        'relations': [
          {'from': '函数极限', 'to': '导数', 'relation': 'prerequisite'},
          {'from': '导数', 'to': '导数', 'relation': '相关'},
        ],
      });

      expect(draft.nodes, hasLength(2));
      expect(draft.nodes.first.name, '函数极限');
      expect(draft.nodes.first.aliases, ['limit']);
      expect(draft.nodes.first.confidence, closeTo(0.9, 1e-9));
      expect(draft.nodes.last.entityType, '定理');
      expect(draft.nodes.last.aliases, ['derivative', '微商']);
      expect(draft.edges, hasLength(1), reason: '自环关系应被丢弃');
      expect(draft.edges.single.fromName, '函数极限');
      expect(draft.edges.single.relationType, '前置知识');
    });

    test('重复实体与重复关系会被去重', () {
      final draft = KnowledgeGraphBuilder.parseExtractionResponse({
        'entities': [
          {'name': '梯度', 'type': '概念'},
          {'name': ' 梯度 ', 'type': '概念'},
          {'name': '梯度', 'type': '概念'},
        ],
        'relations': [
          {'from': '梯度', 'to': '导数', 'relation': '相关'},
          {'from': '梯度', 'to': '导数', 'relation': 'related'},
        ],
      });
      expect(draft.nodes, hasLength(1));
      expect(draft.edges, hasLength(1));
    });

    test('缺少名称的实体被丢弃，缺少端点的关系被丢弃', () {
      final draft = KnowledgeGraphBuilder.parseExtractionResponse({
        'entities': [
          {'type': '概念'},
          {'name': '有效实体', 'type': '概念'},
        ],
        'relations': [
          {'from': '有效实体', 'relation': '相关'},
          {'to': '有效实体', 'relation': '相关'},
        ],
      });
      expect(draft.nodes, hasLength(1));
      expect(draft.edges, isEmpty);
    });

    test('兼容 nodes/relationships 这类别名字段', () {
      final draft = KnowledgeGraphBuilder.parseExtractionResponse({
        'nodes': [
          {'title': '积分', 'category': '概念'},
        ],
        'relationships': [
          {'source': '积分', 'target': '导数', 'label': '依赖'},
        ],
      });
      expect(draft.nodes.single.name, '积分');
      expect(draft.edges.single.relationType, '依赖于');
    });

    test('空响应得到空草稿而不是抛异常', () {
      final draft = KnowledgeGraphBuilder.parseExtractionResponse(const {});
      expect(draft.nodes, isEmpty);
      expect(draft.edges, isEmpty);
    });

    test('置信度被限制在 0 到 1', () {
      final draft = KnowledgeGraphBuilder.parseExtractionResponse({
        'entities': [
          {'name': 'A', 'type': '概念', 'confidence': 7.5},
          {'name': 'B', 'type': '概念', 'confidence': -3},
        ],
        'relations': [],
      });
      expect(draft.nodes.first.confidence, 1.0);
      expect(draft.nodes.last.confidence, 0.0);
    });
  });

  group('parseCrossLibraryResponse', () {
    final nameToNodeId = {
      '梯度': 11,
      '梯度下降': 22,
      '损失函数': 33,
      '导数': 44,
    };

    test('解析跨库关系并保留证据与置信度', () {
      final edges = KnowledgeGraphBuilder.parseCrossLibraryResponse(
        {
          'relations': [
            {
              'from': '梯度',
              'to': '梯度下降',
              'relation': '应用于',
              'evidence': '梯度下降沿负梯度方向迭代更新参数',
              'confidence': 0.85,
            },
          ],
        },
        nameToNodeId: nameToNodeId,
      );
      expect(edges, hasLength(1));
      expect(edges.single.fromName, '梯度');
      expect(edges.single.toName, '梯度下降');
      expect(edges.single.relationType, '应用于');
      expect(edges.single.confidence, closeTo(0.85, 1e-9));
    });

    test('没有证据的跨库关系被丢弃，不为了图谱好看而编造', () {
      final edges = KnowledgeGraphBuilder.parseCrossLibraryResponse(
        {
          'relations': [
            {'from': '梯度', 'to': '损失函数', 'relation': '相关'},
            {
              'from': '梯度',
              'to': '损失函数',
              'relation': '相关',
              'evidence': '两者都出现在同一章',
              'confidence': 0.3,
            },
          ],
        },
        nameToNodeId: nameToNodeId,
      );
      expect(edges, isEmpty, reason: '缺证据或低置信度都必须丢弃');
    });

    test('端点无法映射回真实实体的关系被丢弃', () {
      final edges = KnowledgeGraphBuilder.parseCrossLibraryResponse(
        {
          'relations': [
            {
              'from': '梯度',
              'to': '不存在的概念',
              'relation': '相关',
              'evidence': '有依据的一句话说明',
              'confidence': 0.9,
            },
            {
              'from': '梯度',
              'to': '梯度',
              'relation': '相关',
              'evidence': '自环不应出现',
              'confidence': 0.9,
            },
          ],
        },
        nameToNodeId: nameToNodeId,
      );
      expect(edges, isEmpty);
    });
  });

  group('GraphBuildOutcome', () {
    test('摘要包含处理数量与失败原因', () {
      const ok = GraphBuildOutcome(
        processedDocuments: 3,
        skippedDocuments: 1,
        reusedDocuments: 2,
        createdNodeCount: 12,
        createdEdgeCount: 7,
        failures: [],
      );
      expect(ok.summary, contains('模型抽取 3 份资料'));
      expect(ok.summary, contains('复用 2 份资料'));
      expect(ok.summary, contains('跳过 1 份'));
      expect(ok.hasFailures, isFalse);

      const failed = GraphBuildOutcome(
        processedDocuments: 0,
        skippedDocuments: 0,
        createdNodeCount: 0,
        createdEdgeCount: 0,
        failures: ['资料A：模型未返回知识点'],
      );
      expect(failed.summary, contains('构建失败'));
      expect(failed.hasFailures, isTrue);

      const nothing = GraphBuildOutcome(
        processedDocuments: 0,
        skippedDocuments: 4,
        createdNodeCount: 0,
        createdEdgeCount: 0,
        failures: [],
      );
      expect(nothing.summary, contains('跳过 4 份'));
    });
  });

  group('GraphSourceBundle', () {
    test('没有可用文本时标记为不可抽取', () {
      const bundle = GraphSourceBundle(
        documentId: 1,
        title: '空资料',
        text: '   ',
        hasUsableText: false,
      );
      expect(bundle.hasUsableText, isFalse);
    });
  });
}
