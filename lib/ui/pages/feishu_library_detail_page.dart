import 'package:flutter/material.dart';
import '../../agent/eclaw_context.dart';
import '../../database/app_database.dart';
import '../../database/import_record_repository.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/models/import_record.dart';
import '../../database/models/knowledge_library_record.dart';
import '../../feishu/feishu_controller.dart';
import '../../feishu/feishu_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ask_eclaw_button.dart';
import '../widgets/knowledge_components.dart';
import '../widgets/knowledge_library_editor.dart';
import 'feishu_import_page.dart';
import 'feishu_job_page.dart';
import 'feishu_source_view.dart';
import 'import_record_detail_page.dart';
import 'knowledge_graph_page.dart';
import 'library_practice_page.dart';
import 'interview/interview_prepare_page.dart';

class FeishuLibraryDetailPage extends StatefulWidget {
  const FeishuLibraryDetailPage({
    required this.library,
    this.database,
    super.key,
  });
  final KnowledgeLibraryRecord library;
  final AppDatabase? database;
  @override
  State<FeishuLibraryDetailPage> createState() =>
      _FeishuLibraryDetailPageState();
}

class _FeishuLibraryDetailPageState extends State<FeishuLibraryDetailPage> {
  late KnowledgeLibraryRecord library = widget.library;
  late final controller = FeishuController.forUser(
    library.userId,
    database: widget.database,
  );
  late Future<List<ImportRecord>> records;
  bool syncing = false;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    records = _load();
    controller.addListener(_changed);
  }

  Future<List<ImportRecord>> _load() async {
    final books = await KnowledgeLibraryRepository(
      database: widget.database,
    ).fetchLibraries(library.userId);
    library = books.firstWhere(
      (l) => l.id == library.id,
      orElse: () => library,
    );
    return ImportRecordRepository(
      database: widget.database,
    ).list(library.userId, libraryId: library.id);
  }

  void _changed() {
    if (mounted) {
      setState(() {
        records = _load();
      });
    }
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _sync() async {
    if (syncing || controller.running) return;
    setState(() => syncing = true);
    try {
      await controller.checkConnection();
      if (!controller.connected && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FeishuImportPage(
              userId: library.userId,
              database: widget.database,
              returnAfterConnection: true,
            ),
          ),
        );
      }
      if (!controller.connected) return;
      final plan = await controller.syncPlan(library.id);
      final sourceMode =
          (plan['roots'] as List).firstOrNull?['sync_mode'] as int? ?? 1;
      await controller.importPlan(plan, sourceMode);
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FeishuJobPage(controller: controller),
          ),
        );
      }
    } catch (error) {
      if (error is FeishuException) {
        final db = await controller.database.database;
        await db.update(
          'feishu_containers',
          {
            'sync_status': error.statusCode == 401 ? 'expired' : 'failed',
            'error': '$error',
          },
          where: 'user_id=? AND library_id=?',
          whereArgs: [library.userId, library.id],
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          syncing = false;
          records = _load();
        });
      }
    }
  }

  Future<void> _settings() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改名称、简介和封面'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('删除知识库，保留学习资料'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final repository = KnowledgeLibraryRepository(database: widget.database);
    try {
      if (action == 'edit') {
        final updated = await showKnowledgeLibraryEditor(
          context,
          userId: library.userId,
          repository: repository,
          library: library,
        );
        if (updated != null) _changed();
      } else if (action == 'delete' &&
          await knowledgeConfirmDelete(
            context,
            '删除“${library.name}”？\n停止此知识库的飞书同步，已导入记录、原文和学习成果会移到“待整理”，不会丢失。飞书原文件不会删除。',
          )) {
        await repository.deleteLibraryKeepingRecords(
          userId: library.userId,
          libraryId: library.id,
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _openKnowledgeGraph() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KnowledgeGraphPage(
          initialLibraryIds: <int>[library.id],
          userId: library.userId,
          database: widget.database,
        ),
      ),
    );
    _changed();
  }

  Future<void> _practice() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LibraryPracticePage(
          libraryId: library.id,
          database: widget.database,
        ),
      ),
    );
    _changed();
  }

  Future<void> _interview() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InterviewPreparePage(
          userId: library.userId,
          libraryId: library.id,
          database: widget.database,
        ),
      ),
    );
    _changed();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F8FF),
    appBar: AppBar(
      title: Text(library.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        AskEClawButton(
          database: widget.database,
          scope: EClawContext(knowledgeBaseId: library.id),
        ),
        TextButton(
          onPressed: syncing || controller.running ? null : _settings,
          child: const Text('管理'),
        ),
      ],
    ),
    body: FutureBuilder(
      future: records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('读取失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        final cloud = items.where((r) => r.isFeishu).toList();
        final points = items.fold<int>(
          0,
          (n, r) => n + (r.counts['knowledge_cards'] ?? 0),
        );
        final questions = items.fold<int>(
          0,
          (n, r) => n + (r.counts['practice_questions'] ?? 0),
        );
        return RefreshIndicator(
          onRefresh: () async {
            _changed();
            await records;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 90,
                    height: 104,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0ECFF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      size: 62,
                      color: Color(0xFF7AA5FF),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(library.name, style: AppTextStyles.h2(context)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            Chip(
                              label: Text(library.sourceLabel),
                              visualDensity: VisualDensity.compact,
                            ),
                            Chip(
                              label: Text(library.syncLabel),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        Text(
                          library.description ?? '从飞书同步的学习资料',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.hub_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('查看知识图谱'),
                  subtitle: Text(
                    '默认选中「${library.name}」，可再组合其他知识库',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openKnowledgeGraph,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in const [
                      (0, '概览'),
                      (1, '云文档'),
                      (2, '知识点'),
                      (3, '练习'),
                      (4, '面试'),
                    ])
                      TextButton(
                        onPressed: () => setState(() => tab = item.$1),
                        child: Text(
                          item.$2,
                          style: TextStyle(
                            color: tab == item.$1
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (tab == 0) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (final stat in [
                            ('文档', items.length),
                            ('知识点', points),
                            ('题目', questions),
                          ])
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    stat.$1,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    '${stat.$2}',
                                    style: AppTextStyles.h2(context),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const Divider(),
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '最近同步：${library.syncedAt == null ? '尚未同步' : DateTime.tryParse(library.syncedAt!)?.toLocal().toString().split('.').first ?? library.syncedAt}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          OutlinedButton(
                            onPressed: syncing || controller.running
                                ? null
                                : _sync,
                            child: Text(
                              syncing || controller.running ? '同步中…' : '同步更新',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _practice,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('生成题目'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _practice,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('开始刷题'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _interview,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('模拟面试'),
                    ),
                  ],
                ),
              ],
              if (tab == 3)
                FilledButton(
                  onPressed: _practice,
                  child: const Text('进入现有练习与题目生成'),
                ),
              if (tab == 4)
                FilledButton(
                  onPressed: _interview,
                  child: const Text('进入现有模拟面试'),
                ),
              if (tab <= 2) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tab == 2 ? '文档知识点' : '飞书云文档',
                        style: AppTextStyles.h3(context),
                      ),
                    ),
                    Text(
                      '共 ${cloud.length} 个文档',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < cloud.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${i + 1}'.padLeft(2, '0'),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        cloud[i].title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${cloud[i].statusLabel} · 可查看',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FeishuSourceView(
                              source: cloud[i].anchor,
                              database: widget.database,
                            ),
                          ),
                        );
                        _changed();
                      },
                    ),
                  ),
                if (cloud.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无文档，导入完成后将在这里显示。'),
                  ),
                if (items.any((r) => !r.isFeishu)) ...[
                  const SizedBox(height: 16),
                  Text('本地资料', style: AppTextStyles.h3(context)),
                  for (final record in items.where((r) => !r.isFeishu))
                    ListTile(
                      title: Text(record.title),
                      subtitle: Text(record.statusLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ImportRecordDetailPage(
                              recordId: record.id,
                              userId: library.userId,
                              libraryId: library.id,
                              database: widget.database,
                            ),
                          ),
                        );
                        _changed();
                      },
                    ),
                ],
              ],
            ],
          ),
        );
      },
    ),
  );
}
