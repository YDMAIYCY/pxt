import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/import_record_repository.dart';
import '../../database/knowledge_graph_repository.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_generation_task_record.dart';
import '../../database/models/import_record.dart';
import '../../database/models/knowledge_library_record.dart';
import '../../database/ocr_text_repository.dart';
import '../../database/source_document_repository.dart';
import '../../generator/ai_generation_orchestrator.dart';
import '../../generator/graph_builder_service.dart';
import '../../pipeline/ocr_pipeline_service.dart';
import '../theme/app_theme.dart';
import '../widgets/knowledge_book_cover.dart';
import '../widgets/knowledge_components.dart';
import '../widgets/knowledge_outcome_tile.dart';
import '../widgets/premium_app_chrome.dart';
import 'record_results_page.dart';
import 'record_source_page.dart';

class ImportRecordDetailPage extends StatefulWidget {
  const ImportRecordDetailPage({
    required this.recordId,
    required this.userId,
    this.database,
    this.libraryId,
    this.autoOcr = false,
    super.key,
  });
  final int recordId, userId;
  final int? libraryId;
  final AppDatabase? database;
  final bool autoOcr;
  @override
  State<ImportRecordDetailPage> createState() => _ImportRecordDetailPageState();
}

class _ImportRecordDetailPageState extends State<ImportRecordDetailPage> {
  late Future<({ImportRecord? record, KnowledgeLibraryRecord? library})>
  _future;
  String _query = '', _progress = '';
  bool _busy = false;
  ImportRecordRepository get _repo =>
      ImportRecordRepository(database: widget.database);
  @override
  void initState() {
    super.initState();
    _future = _load();
    if (widget.autoOcr) {
      _future.then((data) {
        if (data.record != null && mounted) _ocr(data.record!);
      });
    }
  }

  Future<({ImportRecord? record, KnowledgeLibraryRecord? library})>
  _load() async {
    final record = await _repo.get(widget.userId, widget.recordId);
    final libs = await KnowledgeLibraryRepository(
      database: widget.database,
    ).fetchLibraries(widget.userId);
    return (
      record: record,
      library: libs.where((l) => l.id == record?.libraryId).firstOrNull,
    );
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _ocr(ImportRecord record) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 'OCR 处理中…';
    });
    try {
      final pipeline = OcrPipelineService(
        ocrTextRepository: OcrTextRepository(database: widget.database),
        sourceDocumentRepository: SourceDocumentRepository(
          database: widget.database,
        ),
        llmConfigRepository: LlmConfigRepository(database: widget.database),
      );
      for (var i = 0; i < record.pages.length; i++) {
        final page = record.pages[i];
        if (page.ocrDone || page.ocrStatus == 'needs_review') continue;
        if (mounted) {
          setState(
            () => _progress = 'OCR 处理中 · ${i + 1}/${record.pages.length} 页',
          );
        }
        await pipeline.runForDocument(document: page);
      }
    } catch (error) {
      _message('识别未完成：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
        await _refresh();
      }
    }
  }

  Future<void> _generate(ImportRecord record, [String? singleType]) async {
    if (_busy) return;
    final selected = <String>{?singleType};
    final types = await showModalBottomSheet<List<String>>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('为本次记录继续生成', style: AppTextStyles.h2(context)),
                const SizedBox(height: 8),
                const Text(
                  '新内容将追加保存，已有卡片、题目和答题记录会保留。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                for (final t in AiTaskType.all)
                  CheckboxListTile(
                    value: selected.contains(t),
                    title: Text(AiTaskType.labelOf(t)),
                    onChanged: (v) => update(() {
                      v == true ? selected.add(t) : selected.remove(t);
                    }),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, selected.toList()),
                    child: const Text('开始生成'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (types == null || !mounted) return;
    final latest = await _repo.get(widget.userId, record.id);
    if (latest == null) return;
    if (latest.pages.any((p) => !p.ocrDone)) {
      _message('请先完成每页 OCR 识别与校对，再生成本次记录的知识内容。');
      return;
    }
    final text = await _repo.sourceText(latest);
    final config = await LlmConfigRepository(
      database: widget.database,
    ).getByUserId(widget.userId);
    if (!mounted) return;
    if (config?.isConfigured != true) {
      _message('请在“我的”中配置现有大模型服务，再开始生成。');
      return;
    }
    if (text.trim().isEmpty) {
      _message('原始资料尚无可用文字，请先识别或校对。');
      return;
    }
    setState(() {
      _busy = true;
      _progress = 'AI 生成中…';
    });
    try {
      final orchestrator = AiGenerationOrchestrator(
        aiGenerationRepository: AiGenerationRepository(
          database: widget.database,
        ),
        knowledgeGraphRepository: KnowledgeGraphRepository(
          database: widget.database,
        ),
      );
      for (final type in types) {
        if (mounted) {
          setState(() => _progress = 'AI 生成中 · ${AiTaskType.labelOf(type)}');
        }
        final result = await orchestrator.generateSingle(
          documentId: latest.anchor.id,
          ocrText: text,
          taskType: type,
          llmConfig: config,
          appendResults: true,
        );
        _message(result.message);
        if (mounted) await _refresh();
      }
    } catch (error) {
      _message('生成未完成，资料已保留：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
        await _refresh();
      }
    }
  }

  Future<void> _sources(ImportRecord record, [int? documentId]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordSourcePage(
          record: record,
          initialDocumentId: documentId,
          database: widget.database,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _results(ImportRecord record, String type, String title) async {
    if (type == 'ocr') {
      await _sources(record);
      return;
    }
    if ((record.counts[type] ?? 0) == 0 &&
        type != 'wrong_questions' &&
        _query.isEmpty) {
      await _generate(record, switch (type) {
        'review_outlines' => AiTaskType.reviewOutline,
        'mindmap_texts' => AiTaskType.mindmapText,
        _ => type,
      });
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordResultsPage(
          record: record,
          type: type,
          title: title,
          query: _query,
          database: widget.database,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _manage(ImportRecord record) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in {
              'rename': '重命名',
              'move': '移动至其他知识库',
              'graph': '重建本条记录的知识图谱',
              'delete': '删除记录及关联内容',
            }.entries)
              ListTile(
                title: Text(e.value),
                onTap: () => Navigator.pop(context, e.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    try {
      if (action == 'rename') {
        final name = await knowledgeTextPrompt(
          context,
          '重命名记录',
          initial: record.title,
        );
        if (name != null) await _repo.rename(widget.userId, record.id, name);
      } else if (action == 'move') {
        final libs = await KnowledgeLibraryRepository(
          database: widget.database,
        ).fetchLibraries(widget.userId);
        if (!mounted) return;
        final target = await showModalBottomSheet<int>(
          context: context,
          useRootNavigator: true,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final l in libs.where((l) => l.id != record.libraryId))
                  ListTile(
                    title: Text(l.name),
                    onTap: () => Navigator.pop(context, l.id),
                  ),
                if (libs.length < 2)
                  const ListTile(title: Text('请先在书架创建另一个知识库。')),
              ],
            ),
          ),
        );
        if (target != null) await _repo.move(widget.userId, record.id, target);
      } else if (action == 'graph') {
        await _rebuildGraph(record);
      } else if (action == 'delete' &&
          await knowledgeConfirmDelete(
            context,
            '删除“${record.title}”？\n本条记录的原资料、OCR、AI 成果、收藏及关联答题记录将一并删除。其他记录不受影响。',
          )) {
        await _repo.delete(widget.userId, record.id);
        if (mounted) Navigator.pop(context);
        return;
      }
      if (mounted) await _refresh();
    } catch (error) {
      _message('$error');
    }
  }

  /// 单条记录重新构建知识图谱：只重跑这条记录的资料，不影响其他记录。
  Future<void> _rebuildGraph(ImportRecord record) async {
    final config = await LlmConfigRepository(
      database: widget.database,
    ).getByUserId(widget.userId);
    if (config == null) {
      if (mounted) _message('还没有配置大模型，请先到「我的」页填写 API Key。');
      return;
    }
    final pages = record.sources;
    if (pages.isEmpty) {
      if (mounted) _message('这条记录还没有可抽取的资料页。');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final builder = KnowledgeGraphBuilder(database: widget.database);
    var succeeded = 0;
    final failures = <String>[];
    for (final page in pages) {
      try {
        await builder.buildForDocument(
          userId: widget.userId,
          documentId: page.id,
          llmConfig: config,
        );
        succeeded++;
      } catch (error) {
        failures.add('${page.title}：$error');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _message(
      failures.isEmpty
          ? '知识图谱已重建：处理 $succeeded 页资料'
          : '重建完成 $succeeded 页，${failures.length} 页失败：${failures.first}',
    );
  }

  Future<void> _tag(ImportRecord record) async {
    final text = await knowledgeTextPrompt(
      context,
      '记录标签（用逗号分隔）',
      initial: record.tags.join('，'),
    );
    if (text != null) {
      await _repo.setTags(widget.userId, record.id, text.split(RegExp('[,，]')));
      if (mounted) await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: PremiumPageBackground(
      child: SafeArea(
        bottom: false,
        child: FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            final record = snapshot.data?.record;
            if (snapshot.hasError ||
                snapshot.connectionState == ConnectionState.done &&
                    record == null) {
              return ListView(
                children: [
                  BackButton(onPressed: () => Navigator.maybePop(context)),
                  KnowledgeEmptyState(
                    title: '记录暂不可用',
                    message: snapshot.hasError
                        ? '${snapshot.error}'
                        : '记录不存在或已删除',
                    action: TextButton(
                      onPressed: _refresh,
                      child: const Text('重试'),
                    ),
                  ),
                ],
              );
            }
            if (record == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final library = snapshot.data?.library;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '记录管理',
                        onPressed: _busy ? null : () => _manage(record),
                        icon: const Icon(Icons.more_horiz),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 88,
                        child: KnowledgeBookCover(
                          title: record.title,
                          subtitle: '学习资料',
                          theme: library?.coverTheme ?? 'papers',
                          color: library?.coverColor ?? bookColors.first,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.h1(context),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${record.sourceLabel} · ${record.anchor.createdAtLabel}\n${record.pageLabel}',
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: Color(0xFF7E90AC),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                if (library != null)
                                  Chip(
                                    label: Text(library.name),
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: AppColors.primarySoft,
                                  ),
                                ...record.tags.map(
                                  (t) => Chip(
                                    label: Text(t),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                ActionChip(
                                  onPressed: () => _tag(record),
                                  label: Text(
                                    record.tags.isEmpty ? '+ 添加标签' : '编辑标签',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .60),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white),
                    ),
                    child: SizedBox(
                      height: 78,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: record.pages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => SourceThumbnail(
                          source: record.pages[i],
                          width: 58,
                          height: 78,
                          onTap: () => _sources(record, record.pages[i].id),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  KnowledgeSearchField(
                    hint: '搜索本次记录生成内容…',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  if (_query.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutcomeSearch(
                        record: record,
                        repository: _repo,
                        query: _query,
                        onOpen: (type, title) => _results(record, type, title),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _busy ? _progress : record.statusLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _ocr(record),
                        child: const Text(
                          '识别 / 重试',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _generate(record),
                        child: const Text(
                          '继续生成',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (record.errors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        record.errors.join('\n'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  if (record.needsLibraryReview)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '旧批次存在跨库资料，请用“移动”确认这条记录的归属。',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 10) / 2;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: knowledgeOutcomes.map((item) {
                          final count = item.type == 'ocr'
                              ? record.pages.length
                              : record.counts[item.type] ?? 0;
                          return SizedBox(
                            width: width,
                            child: OutcomeTile(
                              title: item.title,
                              description: item.description,
                              color: Color(item.color),
                              icon: item.icon,
                              countLabel: count > 0 || item.type == 'ocr'
                                  ? '$count ${item.unit}'
                                  : item.type == 'wrong_questions'
                                  ? '暂无错题'
                                  : '尚未生成 · 点击生成',
                              onTap: () =>
                                  _results(record, item.type, item.title),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
