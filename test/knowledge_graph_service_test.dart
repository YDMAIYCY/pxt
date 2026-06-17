import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/generator/knowledge_graph_extraction_service.dart';

void main() {
  group('knowledge graph contract', () {
    test('database registers concept graph tables and indexes', () {
      final source = File('lib/database/app_database.dart').readAsStringSync();

      expect(AppDatabase.tableKnowledgeConcepts, 'knowledge_concepts');
      expect(AppDatabase.tableKnowledgeConceptLinks, 'knowledge_concept_links');
      expect(
        source,
        contains(r'CREATE TABLE IF NOT EXISTS $tableKnowledgeConcepts'),
      );
      expect(
        source,
        contains(r'CREATE TABLE IF NOT EXISTS $tableKnowledgeConceptLinks'),
      );
      expect(source, contains('idx_knowledge_concepts_library_id'));
      expect(source, contains('idx_knowledge_concepts_weakness_score'));
      expect(source, contains('_upgradeKnowledgeGraphToV12'));
    });

    test('parses concepts and relationships from structured response', () {
      final draft = KnowledgeGraphExtractionService.parseGraphResponse({
        'concepts': [
          {
            'name': '函数单调性',
            'summary': '判断函数增减变化',
            'mastery_score': 42,
            'weakness_score': 70,
            'evidence_text': '导数大于0时函数递增',
          },
          {
            'title': '导数判断',
            'description': '用导数符号判断单调区间',
            'mastery': 65,
            'weakness': 30,
          },
          {'name': ''},
        ],
        'relationships': [
          {'from': '函数单调性', 'to': '导数判断', 'relation': '依赖'},
        ],
      });

      expect(draft.concepts, hasLength(2));
      expect(draft.concepts.first.name, '函数单调性');
      expect(draft.concepts.first.weaknessScore, 70);
      expect(draft.concepts.last.summary, '用导数符号判断单调区间');
      expect(draft.links.single.fromName, '函数单调性');
      expect(draft.links.single.toName, '导数判断');
    });

    test('rejects graph response without concepts', () {
      expect(
        () => KnowledgeGraphExtractionService.parseGraphResponse({
          'concepts': [],
          'relationships': [],
        }),
        throwsFormatException,
      );
    });
  });
}
