import 'dart:convert';

import 'package:flutter/material.dart';

import '../../database/auth_repository.dart';
import '../../database/app_database.dart';
import '../../database/knowledge_graph_repository.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/learning_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/knowledge_graph_records.dart';
import '../../database/models/learning_resource_record.dart';
import '../../database/models/llm_provider_config.dart';
import '../../database/models/source_document_record.dart';
import '../../database/source_document_repository.dart';
import '../../focus/repository/focus_repository.dart';
import '../../generator/learning_resource_service.dart';
import '../theme/app_theme.dart';
import 'ai_interview_page.dart';
import 'image_crop_selection_page.dart';
import 'learning_hub_pages.dart';
import 'learning_errors_page.dart';
import 'ocr_result_page.dart';
import 'practice_review_page.dart';

class LearningWorkspacePage extends StatefulWidget {
  const LearningWorkspacePage({
    required this.documentId,
    this.initialType = 'knowledge_cards',
    this.conceptId,
    this.database,
    this.authRepository,
    this.resourceService,
    super.key,
  });
  final int documentId;
  final int? conceptId;
  final String initialType;
  final AppDatabase? database;
  final AuthRepository? authRepository;
  final LearningResourceService? resourceService;
  @override
  State<LearningWorkspacePage> createState() => _LearningWorkspacePageState();
}

class _LearningWorkspacePageState extends State<LearningWorkspacePage> {
  late final LearningRepository _repository;
  late final LearningResourceService _service;
  late Future<_WorkspaceData> _future;
  late String _type;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _repository = LearningRepository(database: widget.database);
    _service =
        widget.resourceService ??
        LearningResourceService(database: widget.database);
    _type = widget.initialType;
    _future = _load();
  }

  Future<_WorkspaceData> _load() async {
    final user = await (widget.authRepository ?? AuthRepository())
        .getCurrentUserProfile();
    if (user == null) throw StateError('请先登录');
    final document = await SourceDocumentRepository(
      database: widget.database,
    ).getSourceDocumentById(userId: user.id, documentId: widget.documentId);
    if (document == null) throw StateError('资料不存在');
    return _WorkspaceData(
      document,
      await LlmConfigRepository(database: widget.database).getByUserId(user.id),
      await _repository.resources(user.id, document.id),
      await _repository.concepts(user.id, document.id),
      await _repository.report(user.id, document.id),
      await _service.understanding(document.id),
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  LlmProviderConfig _config(_WorkspaceData data) {
    if (data.config?.isConfigured != true) {
      throw StateError('请先在“我的”配置支持当前任务的 AI 模型');
    }
    return data.config!;
  }

  Future<void> _analyze(_WorkspaceData data, {bool crop = false}) async {
    String? path;
    if (crop) {
      path = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) =>
              ImageCropSelectionPage(imagePath: data.document.imagePath),
        ),
      );
      if (path == null) return;
    }
    final config = _config(data);
    final analysis = await _service.analyzeImage(
      data.document,
      config,
      imagePath: path,
    );
    if (!mounted) return;
    final topics = (analysis['topics'] as List).cast<Map>();
    final topic = topics.length == 1
        ? topics.single
        : await showModalBottomSheet<Map>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('选择想学习的主题')),
                  ...topics.map(
                    (t) => ListTile(
                      title: Text('${t['title']}'),
                      subtitle: Text('${t['summary'] ?? ''}'),
                      onTap: () => Navigator.pop(context, t),
                    ),
                  ),
                ],
              ),
            ),
          );
    if (topic == null) return;
    if (!mounted) return;
    final directions = (analysis['directions'] as List? ?? [])
        .map((d) => d.toString())
        .toList();
    String? direction;
    if (directions.isNotEmpty) {
      direction = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('你想了解什么？')),
              ...directions.map(
                (d) => ListTile(
                  title: Text(d),
                  onTap: () => Navigator.pop(context, d),
                ),
              ),
            ],
          ),
        ),
      );
      if (direction == null) return;
    }
    await _service.applyTopic(
      data.document,
      config,
      analysis,
      topic,
      direction: direction,
      imagePath: path,
    );
    // Recommend classification after parsing, while keeping the user's final choice.
    if (mounted) await _libraries(data, recommend: true);
  }

  Future<void> _libraries(_WorkspaceData data, {bool recommend = false}) async {
    final libraries = await KnowledgeLibraryRepository(
      database: widget.database,
    ).fetchLibraries(data.document.userId);
    final selected = (await _repository.libraryIds(
      data.document.userId,
      data.document.id,
    )).toSet();
    var recommendations = <int>[];
    if (recommend && data.config?.isConfigured == true) {
      try {
        recommendations = await _service.recommendLibraries(
          data.document,
          data.config!,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('推荐归类暂不可用，可手动选择：$error')));
        }
      }
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<List<int>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .75,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('关联知识库（可多选）'),
                if (recommendations.isNotEmpty)
                  TextButton(
                    onPressed: () => setSheetState(() {
                      selected
                        ..clear()
                        ..addAll(recommendations);
                    }),
                    child: const Text('采用 AI 推荐'),
                  ),
                if (recommend && recommendations.isEmpty)
                  const Text('没有明确匹配的推荐，请手动选择。'),
                ...libraries.map(
                  (l) => CheckboxListTile(
                    title: Text(l.name),
                    subtitle: recommendations.contains(l.id)
                        ? const Text('AI 推荐')
                        : null,
                    value: selected.contains(l.id),
                    onChanged: (value) => setSheetState(() {
                      if (value == true) {
                        selected.add(l.id);
                      } else {
                        selected.remove(l.id);
                      }
                    }),
                  ),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, selected.toList()),
                  child: const Text('保存归类'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen != null) {
      await _repository.setLibraries(
        data.document.userId,
        data.document.id,
        chosen,
      );
    }
  }

  Future<void> _edit(
    _WorkspaceData data,
    LearningResourceRecord? resource,
  ) async {
    Map<String, dynamic>? cardData;
    int? cardIndex;
    if (resource?.type == 'knowledge_cards') {
      final decoded = jsonDecode(resource!.content);
      if (decoded is Map && decoded['cards'] is List) {
        cardData = Map<String, dynamic>.from(decoded);
        final cards = cardData['cards'] as List;
        cardIndex = await showModalBottomSheet<int>(
          context: context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: cards
                  .asMap()
                  .entries
                  .map(
                    (e) => ListTile(
                      title: Text('${e.value['title']}'),
                      onTap: () => Navigator.pop(context, e.key),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        if (cardIndex == null || !mounted) return;
      }
    }
    final controller = TextEditingController(
      text: cardIndex == null
          ? (resource == null ? '' : resourceText(resource.content))
          : ((cardData!['cards'] as List)[cardIndex]['content'] ?? '')
                .toString(),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(resource == null ? '补充资料与批注' : '编辑内容'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(hintText: '写下你的理解、补充资料或疑问'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    if (result == null) return;
    String content = jsonEncode({'content': result});
    final db = await (widget.database ?? AppDatabase.instance).database;
    if (cardData != null && cardIndex != null) {
      final card = (cardData['cards'] as List)[cardIndex] as Map;
      card['content'] = result;
      content = jsonEncode(cardData);
      await db.update(
        'knowledge_cards',
        {'content': result},
        where: 'document_id = ? AND title = ?',
        whereArgs: [data.document.id, card['title']],
      );
      await db.update(
        'knowledge_concepts',
        {'summary': result},
        where: 'user_id = ? AND name = ?',
        whereArgs: [data.document.userId, card['title']],
      );
    } else if (resource?.type == 'review_outline') {
      await db.update(
        'review_outlines',
        {'outline_text': result},
        where: 'document_id = ?',
        whereArgs: [data.document.id],
      );
    } else if (resource?.type == 'mindmap_text') {
      await db.update(
        'mindmap_texts',
        {'mindmap_text': result},
        where: 'document_id = ?',
        whereArgs: [data.document.id],
      );
    }
    await _repository.saveResource(
      userId: data.document.userId,
      documentId: data.document.id,
      type: resource?.type ?? 'annotation',
      title: resource?.title ?? '我的补充与批注',
      content: content,
      inputText: await _service.sourceText(data.document),
      model: 'user',
    );
  }

  Future<void> _conceptActions(
    _WorkspaceData data,
    KnowledgeConceptRecord concept,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(concept.name),
              subtitle: Text(concept.summary ?? ''),
            ),
            for (final label in [
              '查看卡片',
              '练习',
              'AI 面试',
              '编辑知识点',
              '合并重复知识点',
              '建立跨库关系',
            ])
              ListTile(
                title: Text(label),
                onTap: () => Navigator.pop(context, label),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case '查看卡片':
        setState(() => _type = 'knowledge_cards');
      case '练习':
        await _service.generateConceptQuestions(
          data.document,
          _config(data),
          concept.id,
        );
        if (mounted) {
          await openLearningPage(
            context,
            PracticeReviewPage(
              documentId: data.document.id,
              conceptId: concept.id,
            ),
          );
        }
      case 'AI 面试':
        if (context.mounted) {
          await openLearningPage(
            context,
            AiInterviewPage(
              documentId: data.document.id,
              conceptId: concept.id,
              libraryName: concept.name,
            ),
          );
        }
      case '编辑知识点':
        final name = TextEditingController(text: concept.name);
        final summary = TextEditingController(text: concept.summary);
        final save = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('编辑知识点'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                TextField(
                  controller: summary,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '解释'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          ),
        );
        if (save == true) {
          await _repository.editConcept(
            data.document.userId,
            concept.id,
            name.text,
            summary.text,
          );
        }
        await Future<void>.delayed(Duration.zero);
        name.dispose();
        summary.dispose();
      case '合并重复知识点':
      case '建立跨库关系':
        final candidates = await KnowledgeGraphRepository(
          database: widget.database,
        ).fetchWeakConcepts(userId: data.document.userId, limit: 500);
        if (!mounted) return;
        final target = await showModalBottomSheet<KnowledgeConceptRecord>(
          context: context,
          showDragHandle: true,
          builder: (context) => ListView(
            shrinkWrap: true,
            children: candidates
                .where((c) => c.concept.id != concept.id)
                .map(
                  (c) => ListTile(
                    title: Text(c.concept.name),
                    subtitle: Text(c.documentTitle),
                    onTap: () => Navigator.pop(context, c.concept),
                  ),
                )
                .toList(),
          ),
        );
        if (target == null) return;
        if (action == '合并重复知识点') {
          await _repository.mergeConcepts(
            data.document.userId,
            concept.id,
            target.id,
          );
        } else {
          if (!mounted) return;
          final relation = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ['前置', '相似', '应用', '对比']
                    .map(
                      (r) => ListTile(
                        title: Text('${concept.name} → $r → ${target.name}'),
                        onTap: () => Navigator.pop(context, r),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
          if (relation != null) {
            await _repository.linkConcepts(
              data.document.userId,
              concept.id,
              target.id,
              relation,
            );
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('知识包学习资源')),
    body: FutureBuilder<_WorkspaceData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final versions = data.resources.where((r) => r.type == _type).toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(data.document.title, style: AppTextStyles.h2(context)),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (data.document.sourceType !=
                      SourceDocumentSourceType.pdfDocument) ...[
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() => _analyze(data)),
                      icon: const Icon(Icons.image_search_rounded),
                      label: const Text('理解图片'),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => _analyze(data, crop: true)),
                      child: const Text('选择区域'),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => openLearningPage(
                              context,
                              OcrResultPage(documentId: data.document.id),
                            ),
                          ),
                    child: const Text('识别与校正文本文字'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _libraries(data, recommend: true)),
                    child: const Text('智能归类 / 跨库关联'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await FocusRepository(
                              database: widget.database,
                            ).createTask(
                              userId: data.document.userId,
                              title: '学习：${data.document.title}',
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已加入学习计划，可从“我的”查看'),
                                ),
                              );
                            }
                          }),
                    child: const Text('创建学习计划'),
                  ),
                ],
              ),
              if (data.understanding != null) ...[
                const SizedBox(height: 12),
                Text('内容类型：${data.understanding!['content_type']}'),
                if ((data.understanding!['uncertainties'] as List? ?? [])
                    .isNotEmpty)
                  Text(
                    '待核对：${(data.understanding!['uncertainties'] as List).join('；')}',
                  ),
              ],
              const SizedBox(height: 20),
              Text('共享知识点', style: AppTextStyles.h3(context)),
              if (data.concepts.isEmpty)
                const Text('解析后生成核心知识结构，也可先校正 OCR 文本。'),
              ...data.concepts.map(
                (c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name),
                  subtitle: Text(c.summary ?? ''),
                  trailing: const Icon(Icons.more_horiz_rounded),
                  selected: c.id == widget.conceptId,
                  onTap: _busy
                      ? null
                      : () => _run(() => _conceptActions(data, c)),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '学习资源'),
                items: LearningResourceType.labels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_type != 'annotation')
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await _service.generate(
                                data.document,
                                _config(data),
                                _type,
                              );
                            }),
                      child: Text(versions.isEmpty ? '按需生成' : '打开已保存资源'),
                    ),
                  if (versions.isNotEmpty && _type != 'annotation')
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await _service.generate(
                                data.document,
                                _config(data),
                                _type,
                                force: true,
                              );
                            }),
                      child: const Text('生成新版本'),
                    ),
                  if (_type == 'annotation' ||
                      (versions.isNotEmpty &&
                          ![
                            'flashcards',
                            'practice_questions',
                            'interview_bank',
                            'application_questions',
                          ].contains(_type)))
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => _edit(
                                data,
                                versions.isEmpty ? null : versions.first,
                              ),
                            ),
                      child: const Text('编辑 / 补充'),
                    ),
                ],
              ),
              if (versions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('选择需要的资源再生成，已有结果会保存在本地。'),
                ),
              ...versions.asMap().entries.map((entry) {
                final resource = entry.value;
                final content = _type == 'flashcards'
                    ? FlashcardReview(
                        resource: resource,
                        userId: data.document.userId,
                      )
                    : SelectableText(resourceText(resource.content));
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: entry.key == 0
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${resource.title} · 第 ${resource.version} 版',
                                style: AppTextStyles.h3(context),
                              ),
                              const SizedBox(height: 8),
                              content,
                            ],
                          )
                        : ExpansionTile(
                            title: Text('历史版本 ${resource.version}'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: content,
                              ),
                            ],
                          ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            if ((await _service.sourceText(
                              data.document,
                            )).trim().isNotEmpty) {
                              await _service.generate(
                                data.document,
                                _config(data),
                                'practice_questions',
                              );
                            }
                            if (context.mounted) {
                              await openLearningPage(
                                context,
                                PracticeReviewPage(
                                  documentId: data.document.id,
                                ),
                              );
                            }
                          }),
                    child: const Text('开始练习'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => openLearningPage(
                              context,
                              AiInterviewPage(documentId: data.document.id),
                            ),
                          ),
                    child: const Text('AI 面试'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => openLearningPage(
                              context,
                              LearningErrorsPage(documentId: data.document.id),
                            ),
                          ),
                    child: const Text('学习错误与重练'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('个人学习报告', style: AppTextStyles.h3(context)),
              Text(
                '已记录 ${data.report['attempts']} 条知识点学习反馈，平均反馈分 ${(data.report['average_score'] as num).toStringAsFixed(0)}。评分用于辅助复习，请结合具体反馈判断。',
              ),
              const SizedBox(height: 28),
            ],
          ),
        );
      },
    ),
  );
}

String resourceText(String content) {
  try {
    final data = jsonDecode(content);
    if (data is Map) {
      final text =
          data['content'] ?? data['outline_text'] ?? data['mindmap_text'];
      if (text != null && text.toString().trim().isNotEmpty) {
        return text.toString();
      }
      final items = data['cards'] ?? data['questions'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map(
              (i) => [
                i['title'] ?? i['question_text'] ?? i['front'] ?? '',
                i['content'] ?? i['answer_text'] ?? i['back'] ?? '',
                i['analysis_text'] ?? '',
              ].where((t) => t.toString().trim().isNotEmpty).join('\n'),
            )
            .join('\n\n');
      }
    }
  } catch (_) {}
  return content;
}

class FlashcardReview extends StatefulWidget {
  const FlashcardReview({
    required this.resource,
    required this.userId,
    this.dueOnly = false,
    super.key,
  });
  final LearningResourceRecord resource;
  final int userId;
  final bool dueOnly;
  @override
  State<FlashcardReview> createState() => _FlashcardReviewState();
}

class _FlashcardReviewState extends State<FlashcardReview> {
  final _repository = LearningRepository();
  int _index = 0;
  bool _flipped = false;
  bool _saving = false;
  late Future<Map<int, DateTime>> _schedule;
  @override
  void initState() {
    super.initState();
    _schedule = _repository.cardSchedule(widget.resource.id);
  }

  @override
  void didUpdateWidget(covariant FlashcardReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resource.id != oldWidget.resource.id) {
      _index = 0;
      _flipped = false;
      _schedule = _repository.cardSchedule(widget.resource.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final decoded = jsonDecode(widget.resource.content) as Map;
    final cards = (decoded['cards'] as List? ?? []).whereType<Map>().toList();
    if (cards.isEmpty) return const Text('这份资源没有记忆卡，请重新生成。');
    return FutureBuilder<Map<int, DateTime>>(
      future: _schedule,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final available = [
          for (var i = 0; i < cards.length; i++)
            if (!widget.dueOnly ||
                snapshot.data![i] == null ||
                !snapshot.data![i]!.isAfter(DateTime.now()))
              i,
        ];
        if (available.isEmpty) return const Text('今日卡片已复习完成');
        final cardIndex = available[_index % available.length];
        final card = cards[cardIndex];
        final due = snapshot.data?[cardIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_index % available.length + 1} / ${available.length}${due == null ? '' : ' · 下次复习 ${due.month}/${due.day}'}',
            ),
            InkWell(
              onTap: () => setState(() => _flipped = !_flipped),
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(minHeight: 140),
                color: AppColors.primarySoft,
                child: Text(
                  '${card[_flipped ? 'back' : 'front']}',
                  style: AppTextStyles.body(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _flipped = !_flipped),
              child: Text(_flipped ? '查看问题' : '翻转查看答案'),
            ),
            if (_flipped)
              Wrap(
                spacing: 6,
                children: [
                  for (final entry in {
                    1: '忘记',
                    2: '困难',
                    3: '记得',
                    4: '熟练',
                  }.entries)
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              try {
                                await _repository.reviewCard(
                                  widget.userId,
                                  widget.resource.id,
                                  cardIndex,
                                  entry.key,
                                );
                                if (mounted) {
                                  setState(() {
                                    _schedule = _repository.cardSchedule(
                                      widget.resource.id,
                                    );
                                    _saving = false;
                                    _flipped = false;
                                    _index = (_index + 1) % cards.length;
                                  });
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$error')),
                                  );
                                }
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                      child: Text(entry.value),
                    ),
                ],
              ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _index = (_index + 1) % cards.length;
                      _flipped = false;
                    }),
              child: const Text('下一张'),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceData {
  const _WorkspaceData(
    this.document,
    this.config,
    this.resources,
    this.concepts,
    this.report,
    this.understanding,
  );
  final SourceDocumentRecord document;
  final LlmProviderConfig? config;
  final List<LearningResourceRecord> resources;
  final List<KnowledgeConceptRecord> concepts;
  final Map<String, Object?> report;
  final Map<String, dynamic>? understanding;
}

class DueFlashcardsPage extends StatefulWidget {
  const DueFlashcardsPage({super.key});
  @override
  State<DueFlashcardsPage> createState() => _DueFlashcardsPageState();
}

class _DueFlashcardsPageState extends State<DueFlashcardsPage> {
  int? _userId;
  late final _future = _load();
  Future<List<LearningResourceRecord>> _load() async {
    final user = await AuthRepository().getCurrentUserProfile();
    if (user == null) throw StateError('请先登录');
    _userId = user.id;
    return LearningRepository().dueFlashcards(user.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('今日记忆卡复习')),
    body: FutureBuilder<List<LearningResourceRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('今天没有到期的记忆卡，可以从知识包按需生成。'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: snapshot.data!
              .map(
                (r) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: AppTextStyles.h3(context)),
                        FlashcardReview(
                          key: ValueKey(r.id),
                          resource: r,
                          userId: _userId!,
                          dueOnly: true,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
