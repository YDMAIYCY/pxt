import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/models/ai_result_records.dart';
import '../database/models/document_batch_record.dart';
import '../database/models/source_document_record.dart';

// ========== Debug Demo Data Seeder ==========
// Seeds readable local demo data only for the current debug user.
class DebugDemoDataSeeder {
  DebugDemoDataSeeder({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> seedForUser(int userId) async {
    if (!kDebugMode) {
      return;
    }

    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc();
    final nowText = now.toIso8601String();

    await db.transaction((txn) async {
      await _clearOldDemoData(txn, userId);

      final libraryId = await txn.insert(AppDatabase.tableKnowledgeLibraries, {
        'user_id': userId,
        'name': '[演示] 高等数学知识库',
        'description': '调试用演示知识库，包含 OCR、知识卡片、复习题、错题、知识图谱和基于资料的 AI 对话。',
        'created_at': nowText,
        'updated_at': nowText,
      });

      final batchId = await txn.insert(AppDatabase.tableDocumentBatches, {
        'user_id': userId,
        'library_id': libraryId,
        'title': '[演示] 高等数学学习包',
        'source_type': DocumentBatchSourceType.pdf,
        'original_file_path': 'debug_demo/calculus.pdf',
        'page_count': _demoDocuments.length,
        'created_at': nowText,
        'updated_at': nowText,
      });

      final documentIds = <int>[];
      for (var index = 0; index < _demoDocuments.length; index++) {
        final item = _demoDocuments[index];
        final documentId = await txn.insert(AppDatabase.tableSourceDocuments, {
          'user_id': userId,
          'library_id': libraryId,
          'batch_id': batchId,
          'page_number': index + 1,
          'source_type': SourceDocumentSourceType.pdfPage,
          'image_path': 'debug_demo/calculus_page_${index + 1}.png',
          'original_title': item.title,
          'ocr_status': SourceDocumentOcrStatus.success,
          'ocr_updated_at': nowText,
          'created_at': now
              .subtract(Duration(minutes: index))
              .toIso8601String(),
        });
        documentIds.add(documentId);

        await txn.insert(AppDatabase.tableOcrTexts, {
          'document_id': documentId,
          'raw_text': item.ocrText,
          'clean_text': item.ocrText,
          'final_text': item.ocrText,
          'quality_score': 92 - index * 4,
          'quality_level': 'good',
          'quality_reasons_json': jsonEncode(['演示数据', '结构清晰']),
          'language': 'zh-CN',
          'created_at': nowText,
          'updated_at': nowText,
        });

        await txn.insert(AppDatabase.tableKnowledgeCards, {
          'document_id': documentId,
          'title': item.cardTitle,
          'content': item.cardContent,
          'created_at': nowText,
        });

        await txn.insert(AppDatabase.tableReviewOutlines, {
          'document_id': documentId,
          'title': '${item.cardTitle}复习提纲',
          'outline_text': item.outline,
          'created_at': nowText,
        });

        await txn.insert(AppDatabase.tableMindmapTexts, {
          'document_id': documentId,
          'mindmap_text': item.mindmap,
          'created_at': nowText,
        });
      }

      final wrongQuestionId = await txn.insert(
        AppDatabase.tablePracticeQuestions,
        {
          'document_id': documentIds.first,
          'question_text': '判断函数单调性时为什么不能直接忽略定义域？',
          'answer_text': '因为单调区间必须在定义域内讨论，定义域断点会影响区间划分。',
          'analysis_text': '先求定义域，再求导数符号，最后结合断点和极值点划分单调区间。',
          'difficulty': 'medium',
          'review_status': PracticeQuestionReviewStatus.wrong,
          'last_user_answer': '只要看导数正负就可以。',
          'last_reviewed_at': nowText,
          'wrong_count': 2,
          'next_review_at': now.add(const Duration(days: 1)).toIso8601String(),
          'mastery_score': 35,
          'review_interval_days': 1,
          'correct_streak': 0,
          'question_kind': PracticeQuestionKind.errorAnalysis,
          'expected_keywords_json': jsonEncode(['定义域', '导数符号', '单调区间']),
          'rubric_json': jsonEncode({'定义域': 40, '导数判断': 40, '区间结论': 20}),
          'created_at': nowText,
        },
      );

      await txn.insert(AppDatabase.tablePracticeQuestions, {
        'document_id': documentIds.first,
        'question_text': '函数是什么？请用一句话说明。',
        'answer_text': '函数是从定义域中的每一个输入到唯一输出的对应关系。',
        'analysis_text': '回答时要说明定义域、对应关系和唯一性。',
        'difficulty': 'easy',
        'review_status': PracticeQuestionReviewStatus.pending,
        'wrong_count': 0,
        'question_kind': PracticeQuestionKind.oral,
        'expected_keywords_json': jsonEncode(['定义域', '唯一输出', '对应关系']),
        'created_at': nowText,
      });

      await txn.insert(AppDatabase.tablePracticeQuestions, {
        'document_id': documentIds.last,
        'question_text': '以下哪一项是导数判断极值点的必要步骤？',
        'answer_text': 'B',
        'analysis_text': '需要观察导数在临界点两侧的符号变化。',
        'difficulty': 'easy',
        'review_status': PracticeQuestionReviewStatus.pending,
        'wrong_count': 0,
        'question_kind': PracticeQuestionKind.multipleChoice,
        'options_json': jsonEncode(['A. 只代入原函数', 'B. 看导数符号变化', 'C. 忽略定义域']),
        'expected_keywords_json': jsonEncode(['导数', '符号变化', '极值点']),
        'created_at': nowText,
      });

      await txn.insert(AppDatabase.tableWrongQuestionExplanations, {
        'practice_question_id': wrongQuestionId,
        'user_answer': '只要看导数正负就可以。',
        'correct_answer': '必须先确定定义域，再在定义域内讨论导数符号。',
        'explanation_text': '这是典型的“定义域遗漏”错误，容易导致把不存在的区间也纳入单调性讨论。',
        'created_at': nowText,
      });

      await txn.insert(AppDatabase.tableWrongQuestionTrainings, {
        'wrong_question_id': wrongQuestionId,
        'cause_tags_json': jsonEncode(['定义域遗漏', '步骤不完整']),
        'status': 'pending',
        'created_at': nowText,
      });

      final conceptIds = <int>[];
      for (final concept in _demoConcepts) {
        final conceptId = await txn.insert(AppDatabase.tableKnowledgeConcepts, {
          'user_id': userId,
          'library_id': libraryId,
          'document_id': documentIds.first,
          'name': concept.name,
          'summary': concept.summary,
          'evidence_text': concept.evidence,
          'source_type': 'debug_demo',
          'source_id': wrongQuestionId,
          'mastery_score': concept.mastery,
          'weakness_score': concept.weakness,
          'created_at': nowText,
          'updated_at': nowText,
        });
        conceptIds.add(conceptId);
      }

      for (var index = 0; index < conceptIds.length - 1; index++) {
        await txn.insert(AppDatabase.tableKnowledgeConceptLinks, {
          'user_id': userId,
          'library_id': libraryId,
          'from_concept_id': conceptIds[index],
          'to_concept_id': conceptIds[index + 1],
          'relation_label': index == conceptIds.length - 2 ? '易错点' : '推导',
          'created_at': nowText,
        });
      }

      final sessionId = await txn.insert(AppDatabase.tableAiChatSessions, {
        'user_id': userId,
        'title': '[演示] 基于资料的伴学问答',
        'last_message_preview': '定义域为什么会影响函数单调性？',
        'created_at': nowText,
        'updated_at': nowText,
      });
      await txn.insert(AppDatabase.tableAiChatMessages, {
        'session_id': sessionId,
        'role': 'user',
        'content': '定义域为什么会影响函数单调性？',
        'provider': 'debug_demo',
        'model': 'demo',
        'created_at': nowText,
      });
      await txn.insert(AppDatabase.tableAiChatMessages, {
        'session_id': sessionId,
        'role': 'assistant',
        'content': '因为单调性只能在函数有定义的区间内讨论。演示资料第 1 页指出：先求定义域，再用导数符号划分单调区间。',
        'provider': 'debug_demo',
        'model': 'demo',
        'created_at': now.add(const Duration(seconds: 1)).toIso8601String(),
      });
    });
  }

  Future<void> _clearOldDemoData(Transaction txn, int userId) async {
    await txn.delete(
      AppDatabase.tableAiChatSessions,
      where: 'user_id = ? AND (title LIKE ? OR title LIKE ?)',
      whereArgs: [userId, '[演示]%', '[婕旂ず]%'],
    );
    await txn.delete(
      AppDatabase.tableKnowledgeLibraries,
      where: 'user_id = ? AND (name LIKE ? OR name LIKE ?)',
      whereArgs: [userId, '[演示]%', '[婕旂ず]%'],
    );
    await txn.delete(
      AppDatabase.tableDocumentBatches,
      where: 'user_id = ? AND original_file_path LIKE ?',
      whereArgs: [userId, 'debug_demo/%'],
    );
    await txn.delete(
      AppDatabase.tableSourceDocuments,
      where:
          'user_id = ? AND (image_path LIKE ? OR original_title LIKE ? OR original_title LIKE ?)',
      whereArgs: [userId, 'debug_demo/%', '[演示]%', '[婕旂ず]%'],
    );
  }
}

class _DemoDocument {
  const _DemoDocument({
    required this.title,
    required this.ocrText,
    required this.cardTitle,
    required this.cardContent,
    required this.outline,
    required this.mindmap,
  });

  final String title;
  final String ocrText;
  final String cardTitle;
  final String cardContent;
  final String outline;
  final String mindmap;
}

class _DemoConcept {
  const _DemoConcept({
    required this.name,
    required this.summary,
    required this.evidence,
    required this.mastery,
    required this.weakness,
  });

  final String name;
  final String summary;
  final String evidence;
  final int mastery;
  final int weakness;
}

const List<_DemoDocument> _demoDocuments = [
  _DemoDocument(
    title: '[演示] 高等数学-函数与定义域.pdf 第 1 页',
    ocrText: '函数是定义域到值域的对应关系。讨论函数性质时，必须先确定定义域。',
    cardTitle: '函数与定义域',
    cardContent: '函数不仅是公式，还包含定义域、对应关系和值域。定义域遗漏会影响单调性和极值判断。',
    outline: '- 函数的三要素\n- 定义域优先\n- 单调性讨论不能跨越定义域断点',
    mindmap: '函数\n- 定义域\n- 对应关系\n- 值域\n- 易错：定义域遗漏',
  ),
  _DemoDocument(
    title: '[演示] 高等数学-导数与极值.pdf 第 2 页',
    ocrText: '导数可以判断函数单调性。极值点通常出现在导数为零或导数不存在的位置。',
    cardTitle: '导数判断极值',
    cardContent: '先求导数，再找临界点，最后观察导数符号变化，才能判断极大值或极小值。',
    outline: '- 求导\n- 找临界点\n- 看左右符号\n- 写出极值结论',
    mindmap: '导数判断\n- 单调性\n- 临界点\n- 极值点\n- 易错：只求导不看符号变化',
  ),
];

const List<_DemoConcept> _demoConcepts = [
  _DemoConcept(
    name: '函数单调性',
    summary: '描述函数在某个区间内随自变量变化的趋势。',
    evidence: '讨论单调性必须限定在定义域内。',
    mastery: 62,
    weakness: 38,
  ),
  _DemoConcept(
    name: '导数判断',
    summary: '通过导数符号判断函数增减。',
    evidence: '导数为正通常表示递增，导数为负通常表示递减。',
    mastery: 58,
    weakness: 42,
  ),
  _DemoConcept(
    name: '极值点',
    summary: '函数局部最大或最小的位置。',
    evidence: '极值需要观察临界点左右导数符号变化。',
    mastery: 46,
    weakness: 54,
  ),
  _DemoConcept(
    name: '易错：定义域遗漏',
    summary: '没有先求定义域，导致单调区间或极值判断错误。',
    evidence: '错题中把不存在的区间也纳入了单调性讨论。',
    mastery: 25,
    weakness: 75,
  ),
];
