import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';

import '../database/ai_generation_repository.dart';
import '../database/app_database.dart';
import '../database/import_record_repository.dart';
import '../database/knowledge_graph_repository.dart';
import '../database/knowledge_library_repository.dart';
import '../database/learning_repository.dart';
import '../database/models/learning_resource_record.dart';
import '../database/models/llm_provider_config.dart';
import '../database/models/source_document_record.dart';
import '../llm/minimax_client.dart';
import '../ocr/local_ocr_client.dart';
import 'ai_generation_orchestrator.dart';

class LearningResourceService {
  LearningResourceService({
    LearningRepository? repository,
    AppDatabase? database,
    MiniMaxClient? client,
    AiGenerationOrchestrator? orchestrator,
  }) : _database = database ?? AppDatabase.instance,
       repository = repository ?? LearningRepository(database: database),
       _client = client,
       _orchestrator = orchestrator;
  final AppDatabase _database;
  final LearningRepository repository;
  final MiniMaxClient? _client;
  final AiGenerationOrchestrator? _orchestrator;

  Future<Map<String, dynamic>?> understanding(int documentId) async {
    final db = await _database.database;
    final rows = await db.query(
      'image_understandings',
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['content'] as String) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> analyzeImage(
    SourceDocumentRecord document,
    LlmProviderConfig config, {
    String? imagePath,
  }) async {
    await repository.resources(document.userId, document.id);
    final path = imagePath ?? document.imagePath;
    if (document.sourceType == SourceDocumentSourceType.pdfDocument) {
      throw StateError('整份 PDF 请先执行 OCR；图片理解可从单页或截图开始');
    }
    final bytes = await File(path).readAsBytes();
    final imageHash = LearningRepository.fingerprint(base64Encode(bytes));
    final cached = await understanding(document.id);
    if (cached?['image_fingerprint'] == imageHash &&
        cached?['model'] == config.effectiveModel) {
      return cached!;
    }
    String ocrText = '';
    try {
      ocrText = (await LocalOcrClient().recognizeImage(
        imagePath: path,
      )).cleanText;
    } on LocalOcrException {
      // Diagrams and object photos can still be understood without OCR text.
    }
    final lowerPath = path.toLowerCase();
    final mime = lowerPath.endsWith('.png')
        ? 'image/png'
        : lowerPath.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    final client = _client ?? MiniMaxClient.fromConfig(config);
    final response = await client.generateStructuredJson(
      systemPrompt:
          '你是面向任何年龄和领域的知识分析助手。先检测内容类型，再结合可见文字与视觉结构提取知识。区分观察事实、解释和不确定内容，不猜测看不清的公式、代码或图表。只返回 JSON。',
      userPrompt: '''分析原图，OCR 仅作辅助：$ocrText
返回 {"content_type":"公式/代码/历史/语言/结构图/图表/艺术/摄影/物体/其他",
"visible_text":"可见文本", "uncertainties":["不确定的观察"],
"directions":["学习结构","学习原理","学习用途"],
"topics":[{"title":"独立主题","summary":"学习摘要",
"concepts":[{"name":"知识点","summary":"含义","evidence_text":"图片依据"}],
"relationships":[{"from":"知识点名","to":"知识点名","relation":"前置/应用/对比/相似"}],
"cards":[{"title":"简要卡片","content":"重点与依据"}]}]}。
公式解释符号与推导；代码解释结构和逻辑；历史给出时间人物因果；语言分析段落词汇语法；结构图识别部件和原理；图表说明坐标变量趋势；艺术和摄影分析可观察的技法。
多个独立主题分别列出；普通物体或学习目标不明确时提供 directions 供用户选择；目标明确时 directions 为空。''',
      images: [(base64: base64Encode(bytes), mimeType: mime)],
    );
    final topics = response['topics'];
    if (topics is! List ||
        topics.isEmpty ||
        topics.any(
          (t) =>
              t is! Map ||
              (t['title'] ?? '').toString().trim().isEmpty ||
              (t['summary'] ?? '').toString().trim().isEmpty,
        )) {
      throw const FormatException('图片理解没有返回可选择的学习主题');
    }
    response['image_fingerprint'] = imageHash;
    response['model'] = config.effectiveModel;
    return response;
  }

  Future<void> applyTopic(
    SourceDocumentRecord document,
    LlmProviderConfig config,
    Map<String, dynamic> analysis,
    Map topic, {
    String? direction,
    String? imagePath,
  }) async {
    await repository.resources(document.userId, document.id);
    final selected = direction == null
        ? Map<String, dynamic>.from(topic)
        : await focusTopic(
            document,
            config,
            analysis,
            topic,
            direction,
            imagePath: imagePath,
          );
    topic = selected;
    final prior = await understanding(document.id);
    final selectedTopics = [
      ...(prior?['selected_topics'] as List? ?? []).whereType<Map>().where(
        (t) => t['title'] != selected['title'],
      ),
      selected,
    ];
    final content = {
      ...analysis,
      'selected_topic': selected,
      'selected_topics': selectedTopics,
      'direction': direction,
      'source_image_path': imagePath ?? document.imagePath,
    };
    final db = await _database.database;
    await db.update(
      'source_documents',
      {'original_title': topic['title'].toString()},
      where: 'id = ? AND user_id = ?',
      whereArgs: [document.id, document.userId],
    );
    await db.insert('image_understandings', {
      'document_id': document.id,
      'content': jsonEncode(content),
      'model': config.effectiveModel,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final concepts = selectedTopics
        .expand((t) => t['concepts'] as List? ?? [])
        .whereType<Map>()
        .map(
          (c) => KnowledgeConceptDraft(
            name: (c['name'] ?? '').toString(),
            summary: (c['summary'] ?? '').toString(),
            evidenceText: (c['evidence_text'] ?? '').toString(),
            masteryScore: 0,
            weaknessScore: 0,
          ),
        )
        .toList();
    final links = selectedTopics
        .expand((t) => t['relationships'] as List? ?? [])
        .whereType<Map>()
        .map(
          (c) => KnowledgeConceptLinkDraft(
            fromName: (c['from'] ?? '').toString(),
            toName: (c['to'] ?? '').toString(),
            relationLabel: (c['relation'] ?? '相关').toString(),
          ),
        )
        .toList();
    await KnowledgeGraphRepository(database: _database).replaceGraphForDocument(
      userId: document.userId,
      documentId: document.id,
      libraryId: document.libraryId,
      draft: KnowledgeGraphDraft(concepts: concepts, links: links),
      sourceType: 'visual',
    );
    final cards = (topic['cards'] as List? ?? [])
        .whereType<Map>()
        .where((c) => (c['content'] ?? '').toString().trim().isNotEmpty)
        .map(
          (c) => {
            'title': (c['title'] ?? topic['title']).toString(),
            'content': c['content'].toString(),
          },
        )
        .toList();
    if (cards.isEmpty) {
      cards.add({
        'title': topic['title'].toString(),
        'content': (topic['summary'] ?? '').toString(),
      });
    }
    await AiGenerationRepository(
      database: _database,
    ).replaceKnowledgeCards(documentId: document.id, cards: cards);
    await repository.saveResource(
      userId: document.userId,
      documentId: document.id,
      type: 'knowledge_cards',
      title: topic['title'].toString(),
      content: jsonEncode({'cards': cards}),
      inputText: await sourceText(document),
      model: config.effectiveModel,
    );
  }

  Future<Map<String, dynamic>> focusTopic(
    SourceDocumentRecord document,
    LlmProviderConfig config,
    Map<String, dynamic> analysis,
    Map topic,
    String direction, {
    String? imagePath,
  }) async {
    final path = imagePath ?? document.imagePath;
    final bytes = await File(path).readAsBytes();
    final lower = path.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    final result = await (_client ?? MiniMaxClient.fromConfig(config))
        .generateStructuredJson(
          systemPrompt: '根据用户明确选择的方向理解原图，不能把结构、原理与用途混为一谈。保留图片依据和不确定性，只返回 JSON。',
          userPrompt:
              '选择的主题：${topic['title']}\n学习方向：$direction\n初次观察：${jsonEncode(analysis)}\n返回该方向的 {"title":"主题标题","summary":"摘要","concepts":[{"name":"知识点","summary":"解释","evidence_text":"图片依据"}],"relationships":[{"from":"名称","to":"名称","relation":"关系"}],"cards":[{"title":"卡片标题","content":"简要要点与依据"}]}。',
          images: [(base64: base64Encode(bytes), mimeType: mime)],
        );
    if ((result['title'] ?? '').toString().trim().isEmpty ||
        (result['summary'] ?? '').toString().trim().isEmpty) {
      throw const FormatException('没有返回所选方向的学习内容，请重试');
    }
    return result;
  }

  Future<String> sourceText(SourceDocumentRecord document) async {
    final snapshot = await ImportRecordRepository(
      database: _database,
    ).sourceSnapshot(document.userId, document.id);
    final concepts = await repository.concepts(document.userId, document.id);
    final edited = await repository.resources(document.userId, document.id);
    final seen = <String>{};
    final additions = edited
        .where((r) => seen.add(r.type) && r.model == 'user')
        .map((r) => r.content)
        .join('\n');
    return [
      if (snapshot.text.isNotEmpty) snapshot.text,
      if (concepts.isNotEmpty)
        '已确认知识点：${concepts.map((c) => '${c.name}: ${c.summary}').join('\n')}',
      if (additions.isNotEmpty) '用户补充与修订：$additions',
    ].join('\n\n');
  }

  Future<LearningResourceRecord> generate(
    SourceDocumentRecord document,
    LlmProviderConfig config,
    String type, {
    bool force = false,
  }) async {
    final source = await sourceText(document);
    if (source.trim().isEmpty) throw StateError('请先识别文字或理解图片');
    final snapshot = await ImportRecordRepository(
      database: _database,
    ).sourceSnapshot(document.userId, document.id);
    final old = await repository.resources(
      document.userId,
      document.id,
      type: type,
    );
    if (!force && old.isNotEmpty && old.first.model == 'user') return old.first;
    if (!force &&
        old.isNotEmpty &&
        old.first.fingerprint == LearningRepository.fingerprint(source) &&
        old.first.model == config.effectiveModel) {
      return old.first;
    }
    if ([
      'knowledge_cards',
      'review_outline',
      'mindmap_text',
      'practice_questions',
    ].contains(type)) {
      final orchestrator =
          _orchestrator ??
          AiGenerationOrchestrator(
            miniMaxClient: _client,
            aiGenerationRepository: AiGenerationRepository(database: _database),
            knowledgeGraphRepository: KnowledgeGraphRepository(
              database: _database,
            ),
            learningRepository: repository,
          );
      final result = force
          ? await orchestrator.regenerateWithFeedback(
              documentId: document.id,
              ocrText: source,
              taskType: type,
              llmConfig: config,
              currentResultText: old.isEmpty ? '' : old.first.content,
              feedback: '请根据当前资料重新生成一个完整的新版本。',
            )
          : await orchestrator.generateSingle(
              documentId: document.id,
              ocrText: source,
              taskType: type,
              llmConfig: config,
            );
      if (!result.success) throw StateError(result.message);
      final saved = await repository.resources(
        document.userId,
        document.id,
        type: type,
      );
      if (saved.isNotEmpty &&
          saved.first.fingerprint == LearningRepository.fingerprint(source) &&
          saved.first.model == config.effectiveModel) {
        return saved.first;
      }
      final tasks = await AiGenerationRepository(
        database: _database,
      ).fetchLatestTasksByDocument(document.id);
      final task = tasks.firstWhere((t) => t.taskType == type);
      return repository.saveResource(
        userId: document.userId,
        documentId: document.id,
        type: type,
        title: LearningResourceType.labels[type]!,
        content: task.resultText!,
        inputText: source,
        model: config.effectiveModel,
      );
    }
    if (!LearningResourceType.labels.containsKey(type) ||
        type == 'annotation') {
      throw ArgumentError('资源类型无效');
    }
    final response = await (_client ?? MiniMaxClient.fromConfig(config))
        .generateStructuredJson(
          systemPrompt: '你是全领域学习助手。基于资料和知识点生成学习资源，区分原始资料与补充解释，不编造依据。返回 JSON。',
          userPrompt:
              '''资料：$source
按需生成 ${LearningResourceType.labels[type]}。
笔记用分层 Markdown；知识树用层级树；深度讲解包括原理、例子、常见误区和迁移应用。
返回 {"title":"标题","content":"完整内容"}。
如果资源为记忆闪卡，必须额外返回 "cards":[{"front":"问题","back":"答案"}]。
如果资源为 AI 面试题库或概念辨析与应用题，必须额外返回 "questions":[{"question_text":"问题","answer_text":"参考答案","analysis_text":"解析","difficulty":"基础/应用/深入","question_kind":"oral/short_answer"}]。''',
        );
    if (type == 'flashcards') {
      final cards = response['cards'];
      if (cards is! List ||
          cards.isEmpty ||
          cards.any(
            (c) =>
                c is! Map ||
                (c['front'] ?? '').toString().trim().isEmpty ||
                (c['back'] ?? '').toString().trim().isEmpty,
          )) {
        throw const FormatException('记忆闪卡缺少正反面内容');
      }
    }
    if (['notes', 'knowledge_tree', 'deep_explanation'].contains(type) &&
        (response['content'] ?? '').toString().trim().isEmpty) {
      throw const FormatException('生成内容为空，请重试');
    }
    if (type == 'interview_bank' || type == 'application_questions') {
      final questions = AiGenerationOrchestrator.parsePracticeQuestionsForTest(
        response,
      );
      await AiGenerationRepository(
        database: _database,
      ).appendPracticeQuestions(documentId: document.id, questions: questions);
    }
    return repository.saveResource(
      userId: document.userId,
      documentId: document.id,
      type: type,
      title: (response['title'] ?? LearningResourceType.labels[type])
          .toString(),
      content: jsonEncode(response),
      inputText: source,
      model: config.effectiveModel,
      sourceVersionId: snapshot.id,
    );
  }

  Future<List<int>> recommendLibraries(
    SourceDocumentRecord document,
    LlmProviderConfig config,
  ) async {
    final libraries = await KnowledgeLibraryRepository(
      database: _database,
    ).fetchLibraries(document.userId);
    final source = await sourceText(document);
    if (source.isEmpty) throw StateError('请先解析资料');
    final response = await (_client ?? MiniMaxClient.fromConfig(config))
        .generateStructuredJson(
          systemPrompt: '根据资料内容推荐知识库，不能虚构 ID。只返回 JSON。',
          userPrompt:
              '资料：$source\n候选知识库：${libraries.map((l) => '${l.id}: ${l.name} ${l.description ?? ''}').join('\n')}\n返回 {"library_ids":[整数 ID]}，可多选；不匹配则返回空数组。',
        );
    final ids = (response['library_ids'] as List? ?? [])
        .whereType<int>()
        .toSet();
    return libraries.where((l) => ids.contains(l.id)).map((l) => l.id).toList();
  }

  Future<void> generateConceptQuestions(
    SourceDocumentRecord document,
    LlmProviderConfig config,
    int conceptId,
  ) async {
    final ids = await repository.questionsForConcept(
      document.userId,
      conceptId,
    );
    final record = await ImportRecordRepository(
      database: _database,
    ).forDocument(document.userId, document.id);
    if (record == null) throw StateError('资料缺少导入记录');
    if (ids.isNotEmpty) {
      final db = await _database.database;
      final local = await db.rawQuery(
        '''SELECT id FROM practice_questions
        WHERE id IN (${List.filled(ids.length, '?').join(',')})
          AND document_id IN (SELECT id FROM source_documents WHERE import_record_id = ?)''',
        [...ids, record.id],
      );
      if (local.isNotEmpty) return;
    }
    final snapshot = await ImportRecordRepository(
      database: _database,
    ).sourceSnapshot(document.userId, document.id);
    final concept = (await repository.concepts(
      document.userId,
      document.id,
    )).firstWhere((c) => c.id == conceptId);
    final source = await sourceText(document);
    final response = await (_client ?? MiniMaxClient.fromConfig(config))
        .generateStructuredJson(
          systemPrompt: '基于用户资料生成全领域知识练习，只返回 JSON，不编造原始依据。',
          userPrompt:
              '资料：$source\n专门考察 ${concept.name}：${concept.summary}\n返回 {"questions":[{"question_text":"问题","answer_text":"答案","analysis_text":"解析","difficulty":"基础","question_kind":"oral"}]}，生成 3 道题。',
        );
    final questions = AiGenerationOrchestrator.parsePracticeQuestionsForTest(
      response,
    );
    await AiGenerationRepository(database: _database).appendPracticeQuestions(
      documentId: document.id,
      questions: questions
          .map((q) => {...q, 'source_version_id': '${snapshot.id}'})
          .toList(),
    );
    final db = await _database.database;
    for (final q in questions) {
      final rows = await db.query(
        'practice_questions',
        columns: ['id'],
        where: 'document_id = ? AND question_text = ?',
        whereArgs: [document.id, q['question_text']],
      );
      for (final row in rows) {
        await db.insert('question_concepts', {
          'question_id': row['id'],
          'concept_id': conceptId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Future<List<int>> createExam(
    SourceDocumentRecord document,
    LlmProviderConfig config, {
    required int count,
    required String difficulty,
  }) async {
    if (count < 1 || count > 20) throw ArgumentError('题量应为 1 到 20 道');
    final snapshot = await ImportRecordRepository(
      database: _database,
    ).sourceSnapshot(document.userId, document.id);
    final source = await sourceText(document);
    if (source.trim().isEmpty) throw StateError('请先解析这份资料');
    final response = await (_client ?? MiniMaxClient.fromConfig(config))
        .generateStructuredJson(
          systemPrompt: '基于资料智能组卷，覆盖概念辨析和应用，标明参考答案与解析。不编造来源，只返回 JSON。',
          userPrompt:
              '资料：$source\n生成 $count 道难度为“$difficulty”的题目，返回 {"questions":[{"question_text":"题目","answer_text":"答案","analysis_text":"解析","difficulty":"$difficulty","question_kind":"short_answer"}]}。',
        );
    final questions = AiGenerationOrchestrator.parsePracticeQuestionsForTest(
      response,
    );
    if (questions.length != count) {
      throw FormatException('模型返回了 ${questions.length} 道题，要求 $count 道，请重试');
    }
    if (questions.map((q) => q['question_text']).toSet().length != count) {
      throw const FormatException('组卷包含重复题目，请重试');
    }
    await AiGenerationRepository(database: _database).appendPracticeQuestions(
      documentId: document.id,
      questions: questions
          .map((q) => {...q, 'source_version_id': '${snapshot.id}'})
          .toList(),
    );
    await repository.saveResource(
      userId: document.userId,
      documentId: document.id,
      type: 'application_questions',
      title: '$difficulty · $count 道智能组卷',
      content: jsonEncode(response),
      inputText: source,
      model: config.effectiveModel,
      sourceVersionId: snapshot.id,
    );
    final db = await _database.database;
    final ids = <int>[];
    for (final q in questions) {
      final rows = await db.query(
        'practice_questions',
        columns: ['id'],
        where:
            'document_id = ? AND question_text = ? AND source_version_id = ?',
        whereArgs: [document.id, q['question_text'], snapshot.id],
      );
      ids.add(rows.first['id'] as int);
    }
    return ids;
  }
}
