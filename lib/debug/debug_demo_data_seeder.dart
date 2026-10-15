import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/models/ai_result_records.dart';
import '../database/models/document_batch_record.dart';
import '../database/models/source_document_record.dart';

// ========== Debug Demo Data Seeder ==========
// Seeds local-only data for the current debug user.
class DebugDemoDataSeeder {
  DebugDemoDataSeeder({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<int> seedIsolatedDemo() async {
    if(!kDebugMode) throw StateError('演示数据仅限 Debug 环境');
    await _database.ensureSchemaReady();
    final db=await _database.database;
    final existing=await db.query('users',columns:['id'],where:'username=?',whereArgs:['__eclaw_debug_demo__']);
    final userId=existing.isNotEmpty ? existing.single['id'] as int : await db.insert('users',{
      'username':'__eclaw_debug_demo__','password_hash':'disabled-debug-account','password_salt':'debug-only','is_active':0,'updated_at':DateTime.now().toUtc().toIso8601String(),
      'created_at':DateTime.now().toUtc().toIso8601String(),
    });
    await seedForUser(userId);
    return userId;
  }

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
        'description':
            '用于验证 GraphRAG、Adaptive KG、Next-Best-Action、EClaw 问答、练习题、错题和 AI 面试的本地调试数据。',
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

      final questionIds = <String, int>{};
      for (final question in _demoQuestions) {
        final id = await txn.insert(AppDatabase.tablePracticeQuestions, {
          'document_id': documentIds[question.documentIndex],
          'question_text': question.questionText,
          'answer_text': question.answerText,
          'analysis_text': question.analysisText,
          'difficulty': question.difficulty,
          'review_status': question.reviewStatus,
          'last_user_answer': question.lastUserAnswer,
          'last_reviewed_at': question.lastUserAnswer == null ? null : nowText,
          'wrong_count': question.wrongCount,
          'next_review_at': now
              .add(Duration(days: question.nextReviewDays))
              .toIso8601String(),
          'mastery_score': question.masteryScore,
          'review_interval_days': question.nextReviewDays,
          'correct_streak': question.correctStreak,
          'parent_question_id': null,
          'question_kind': question.questionKind,
          'options_json': question.options.isEmpty
              ? null
              : jsonEncode(question.options),
          'rubric_json': question.rubric.isEmpty
              ? null
              : jsonEncode(question.rubric),
          'expected_keywords_json': jsonEncode(question.expectedKeywords),
          'created_at': nowText,
        });
        questionIds[question.key] = id;
      }

      final wrongQuestionId = questionIds['domain_mistake']!;
      await txn.insert(AppDatabase.tableWrongQuestionExplanations, {
        'practice_question_id': wrongQuestionId,
        'user_answer': '只要看导数正负就可以。',
        'correct_answer': '必须先确定定义域，再在定义域内讨论导数符号。',
        'explanation_text': '这是典型的“定义域遗漏”错误。函数单调区间不能跨过定义域断点，否则会把不存在的区间也纳入讨论。',
        'created_at': nowText,
      });

      await txn.insert(AppDatabase.tableWrongQuestionTrainings, {
        'wrong_question_id': wrongQuestionId,
        'cause_tags_json': jsonEncode(['定义域遗漏', '步骤不完整', '导数判断机械套用']),
        'status': 'pending',
        'created_at': nowText,
        'completed_at': null,
      });

      final conceptIds = <String, int>{};
      for (final concept in _demoConcepts) {
        final documentId = documentIds[concept.documentIndex];
        final conceptId = await txn.insert(AppDatabase.tableKnowledgeConcepts, {
          'user_id': userId,
          'library_id': libraryId,
          'document_id': documentId,
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
        conceptIds[concept.key] = conceptId;
      }

      for (final link in _demoLinks) {
        await txn.insert(AppDatabase.tableKnowledgeConceptLinks, {
          'user_id': userId,
          'library_id': libraryId,
          'from_concept_id': conceptIds[link.fromKey],
          'to_concept_id': conceptIds[link.toKey],
          'relation_label': link.label,
          'created_at': nowText,
        });
      }

      final sessionId = await txn.insert(AppDatabase.tableAiChatSessions, {
        'user_id': userId,
        'title': '[演示] EClaw 图谱问答',
        'last_message_preview': '为什么我总是错函数单调性？',
        'created_at': nowText,
        'updated_at': nowText,
      });
      await txn.insert(AppDatabase.tableAiChatMessages, {
        'session_id': sessionId,
        'role': 'user',
        'content': '为什么我总是错函数单调性？',
        'provider': 'debug_demo',
        'model': 'demo',
        'created_at': nowText,
      });
      await txn.insert(AppDatabase.tableAiChatMessages, {
        'session_id': sessionId,
        'role': 'assistant',
        'content':
            '从你的知识图谱看，函数单调性相关节点的薄弱点集中在“定义域遗漏”和“导数符号变化”。建议先补“定义域”，再做 3 道导数判断题。',
        'provider': 'debug_demo',
        'model': 'demo',
        'created_at': now.add(const Duration(seconds: 1)).toIso8601String(),
      });
    });
  }

  Future<void> _clearOldDemoData(Transaction txn, int userId) async {
    await txn.delete(
      AppDatabase.tableAiChatSessions,
      where: 'user_id = ? AND (title LIKE ? OR title LIKE ? OR title LIKE ?)',
      whereArgs: [userId, '[演示]%', '[婕旂ず]%', '[濠曟梻銇歖%'],
    );
    await txn.delete(
      AppDatabase.tableKnowledgeLibraries,
      where: 'user_id = ? AND (name LIKE ? OR name LIKE ? OR name LIKE ?)',
      whereArgs: [userId, '[演示]%', '[婕旂ず]%', '[濠曟梻銇歖%'],
    );
    await txn.delete(
      AppDatabase.tableDocumentBatches,
      where: 'user_id = ? AND original_file_path LIKE ?',
      whereArgs: [userId, 'debug_demo/%'],
    );
    await txn.delete(
      AppDatabase.tableSourceDocuments,
      where:
          'user_id = ? AND (image_path LIKE ? OR original_title LIKE ? OR original_title LIKE ? OR original_title LIKE ?)',
      whereArgs: [userId, 'debug_demo/%', '[演示]%', '[婕旂ず]%', '[濠曟梻銇歖%'],
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

class _DemoQuestion {
  const _DemoQuestion({
    required this.key,
    required this.documentIndex,
    required this.questionText,
    required this.answerText,
    required this.analysisText,
    required this.difficulty,
    required this.reviewStatus,
    required this.wrongCount,
    required this.masteryScore,
    required this.nextReviewDays,
    required this.correctStreak,
    required this.questionKind,
    required this.expectedKeywords,
    this.lastUserAnswer,
    this.options = const [],
    this.rubric = const {},
  });

  final String key;
  final int documentIndex;
  final String questionText;
  final String answerText;
  final String analysisText;
  final String difficulty;
  final String reviewStatus;
  final String? lastUserAnswer;
  final int wrongCount;
  final int masteryScore;
  final int nextReviewDays;
  final int correctStreak;
  final String questionKind;
  final List<String> expectedKeywords;
  final List<String> options;
  final Map<String, int> rubric;
}

class _DemoConcept {
  const _DemoConcept({
    required this.key,
    required this.documentIndex,
    required this.name,
    required this.summary,
    required this.evidence,
    required this.mastery,
    required this.weakness,
  });

  final String key;
  final int documentIndex;
  final String name;
  final String summary;
  final String evidence;
  final int mastery;
  final int weakness;
}

class _DemoLink {
  const _DemoLink({
    required this.fromKey,
    required this.toKey,
    required this.label,
  });

  final String fromKey;
  final String toKey;
  final String label;
}

const List<_DemoDocument> _demoDocuments = [
  _DemoDocument(
    title: '[演示] 高等数学-函数与定义域.pdf 第 1 页',
    ocrText: '函数是定义域到值域的对应关系。讨论函数性质时，必须先确定定义域。单调区间只能在定义域内部讨论，不能跨过定义域断点。',
    cardTitle: '函数与定义域',
    cardContent: '函数不只是公式，还包含定义域、对应关系和值域。定义域遗漏会影响单调性、极值和图像判断。',
    outline: '- 函数三要素\n- 定义域优先\n- 单调区间不能跨越定义域断点\n- 常见错因：只看导数符号',
    mindmap: '函数\n- 定义域\n- 对应关系\n- 值域\n- 易错：定义域遗漏',
  ),
  _DemoDocument(
    title: '[演示] 高等数学-导数与极值.pdf 第 2 页',
    ocrText: '导数可以判断函数单调性。极值点通常出现在导数为零或导数不存在的位置，但需要观察导数在临界点左右的符号变化。',
    cardTitle: '导数判断极值',
    cardContent: '先求导数，再找临界点，最后观察导数符号变化。只求导不看左右符号变化，容易误判极值点。',
    outline: '- 求导\n- 找临界点\n- 看左右符号\n- 写出极值结论\n- 常见错因：只求导不判断符号变化',
    mindmap: '导数判断\n- 单调性\n- 临界点\n- 极值点\n- 易错：只求导不看符号变化',
  ),
  _DemoDocument(
    title: '[演示] 高等数学-错题复盘.pdf 第 3 页',
    ocrText: '错题复盘要记录错因。函数单调性错题常见原因包括定义域遗漏、导数符号变化判断不完整、极值点与最值点混淆。',
    cardTitle: '错题复盘方法',
    cardContent: '复盘不是只看答案，而是把错误归因到知识点：概念缺口、步骤遗漏、计算错误或题型迁移失败。',
    outline: '- 记录原错因\n- 映射到知识点\n- 找前置知识\n- 生成专项训练',
    mindmap: '错题复盘\n- 错因 DNA\n- 知识点映射\n- 前置知识\n- 专项训练',
  ),
];

const List<_DemoQuestion> _demoQuestions = [
  _DemoQuestion(
    key: 'domain_mistake',
    documentIndex: 0,
    questionText: '判断函数单调性时为什么不能直接忽略定义域？',
    answerText: '因为单调区间必须在定义域内讨论，定义域断点会影响区间划分。',
    analysisText: '先求定义域，再求导数符号，最后结合断点和临界点划分单调区间。',
    difficulty: 'medium',
    reviewStatus: PracticeQuestionReviewStatus.wrong,
    lastUserAnswer: '只要看导数正负就可以。',
    wrongCount: 3,
    masteryScore: 25,
    nextReviewDays: 0,
    correctStreak: 0,
    questionKind: PracticeQuestionKind.errorAnalysis,
    expectedKeywords: ['定义域', '导数符号', '单调区间'],
    rubric: {'定义域': 40, '导数判断': 40, '区间结论': 20},
  ),
  _DemoQuestion(
    key: 'function_oral',
    documentIndex: 0,
    questionText: '函数是什么？请用一句话说明。',
    answerText: '函数是从定义域中的每一个输入到唯一输出的对应关系。',
    analysisText: '回答时要说明定义域、对应关系和唯一性。',
    difficulty: 'easy',
    reviewStatus: PracticeQuestionReviewStatus.pending,
    wrongCount: 0,
    masteryScore: 45,
    nextReviewDays: 0,
    correctStreak: 1,
    questionKind: PracticeQuestionKind.oral,
    expectedKeywords: ['定义域', '唯一输出', '对应关系'],
  ),
  _DemoQuestion(
    key: 'derivative_choice',
    documentIndex: 1,
    questionText: '以下哪一项是导数判断极值点的必要步骤？',
    answerText: 'B',
    analysisText: '需要观察导数在临界点两侧的符号变化。',
    difficulty: 'easy',
    reviewStatus: PracticeQuestionReviewStatus.pending,
    wrongCount: 1,
    masteryScore: 50,
    nextReviewDays: 1,
    correctStreak: 1,
    questionKind: PracticeQuestionKind.multipleChoice,
    expectedKeywords: ['导数', '符号变化', '极值点'],
    options: ['A. 只代入原函数', 'B. 看导数符号变化', 'C. 忽略定义域', 'D. 只看函数名称'],
  ),
  _DemoQuestion(
    key: 'gap_short_answer',
    documentIndex: 2,
    questionText: '如果一道单调性题反复做错，应该如何复盘？',
    answerText: '先标注错因，再映射到知识点，最后补前置知识并做专项训练。',
    analysisText: '这道题用于验证错因 DNA 和 Next-Best-Action 推荐。',
    difficulty: 'medium',
    reviewStatus: PracticeQuestionReviewStatus.pending,
    wrongCount: 0,
    masteryScore: 30,
    nextReviewDays: 0,
    correctStreak: 0,
    questionKind: PracticeQuestionKind.shortAnswer,
    expectedKeywords: ['错因', '知识点', '前置知识', '专项训练'],
  ),
];

const List<_DemoConcept> _demoConcepts = [
  _DemoConcept(
    key: 'domain',
    documentIndex: 0,
    name: '定义域',
    summary: '函数允许输入的自变量范围，是讨论函数性质的前提。',
    evidence: '资料第 1 页：讨论函数性质时，必须先确定定义域。',
    mastery: 35,
    weakness: 72,
  ),
  _DemoConcept(
    key: 'monotonicity',
    documentIndex: 0,
    name: '函数单调性',
    summary: '描述函数在某个区间内随自变量变化的趋势。',
    evidence: '资料第 1 页：单调区间只能在定义域内部讨论。',
    mastery: 52,
    weakness: 64,
  ),
  _DemoConcept(
    key: 'derivative_sign',
    documentIndex: 1,
    name: '导数符号判断',
    summary: '通过导数正负判断函数递增或递减。',
    evidence: '资料第 2 页：导数可以判断函数单调性。',
    mastery: 48,
    weakness: 58,
  ),
  _DemoConcept(
    key: 'critical_point',
    documentIndex: 1,
    name: '临界点',
    summary: '导数为零或导数不存在的位置，是极值判断的重要候选点。',
    evidence: '资料第 2 页：极值点通常出现在导数为零或导数不存在的位置。',
    mastery: 42,
    weakness: 61,
  ),
  _DemoConcept(
    key: 'extreme_point',
    documentIndex: 1,
    name: '极值点',
    summary: '函数局部最大或局部最小的位置。',
    evidence: '资料第 2 页：需要观察导数在临界点左右的符号变化。',
    mastery: 38,
    weakness: 67,
  ),
  _DemoConcept(
    key: 'domain_mistake',
    documentIndex: 2,
    name: '易错：定义域遗漏',
    summary: '没有先求定义域，导致单调区间或极值判断错误。',
    evidence: '错题中把不存在的区间也纳入了单调性讨论。',
    mastery: 20,
    weakness: 88,
  ),
  _DemoConcept(
    key: 'wrong_cause',
    documentIndex: 2,
    name: '错因 DNA',
    summary: '把错误原因归类到知识点、步骤或题型迁移问题。',
    evidence: '资料第 3 页：错题复盘要记录错因，并映射到知识点。',
    mastery: 30,
    weakness: 70,
  ),
];

const List<_DemoLink> _demoLinks = [
  _DemoLink(fromKey: 'domain', toKey: 'monotonicity', label: '前置'),
  _DemoLink(fromKey: 'derivative_sign', toKey: 'monotonicity', label: '判断方法'),
  _DemoLink(fromKey: 'derivative_sign', toKey: 'critical_point', label: '推导'),
  _DemoLink(fromKey: 'critical_point', toKey: 'extreme_point', label: '前置'),
  _DemoLink(fromKey: 'domain_mistake', toKey: 'monotonicity', label: '易错点'),
  _DemoLink(fromKey: 'domain', toKey: 'domain_mistake', label: '补救'),
  _DemoLink(fromKey: 'wrong_cause', toKey: 'domain_mistake', label: '归因'),
  _DemoLink(fromKey: 'wrong_cause', toKey: 'domain', label: '补前置'),
];
