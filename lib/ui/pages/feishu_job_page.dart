import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../feishu/feishu_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_kit.dart';
import 'feishu_import_page.dart';
import 'feishu_import_confirm_page.dart';

class FeishuJobPage extends StatefulWidget {
  const FeishuJobPage({required this.controller, super.key});
  final FeishuController controller;
  @override
  State<FeishuJobPage> createState() => _FeishuJobPageState();
}

class _FeishuJobPageState extends State<FeishuJobPage> {
  late Future<List<Map<String, Object?>>> jobs;
  @override
  void initState() {
    super.initState();
    jobs = _load();
    widget.controller.addListener(_refresh);
  }

  Future<List<Map<String, Object?>>> _load() async {
    await widget.controller.initialize();
    return widget.controller.repository.jobs(widget.controller.userId);
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        jobs = _load();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _resume(int id) async {
    try {
      await widget.controller.checkConnection();
      if (!widget.controller.connected && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FeishuImportPage(
              userId: widget.controller.userId,
              database: widget.controller.database,
              returnAfterConnection: true,
            ),
          ),
        );
      }
      if (widget.controller.connected) unawaited(widget.controller.run(id));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('飞书导入任务')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (widget.controller.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.tintOf(AppColors.accentSky, 0.09),
                borderRadius: BorderRadius.circular(AppRadii.cardSmall),
                border: Border.all(
                  color: AppColors.tintOf(AppColors.accentSky, 0.20),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.accentSky,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.controller.message,
                      style: AppTextStyles.caption(
                        context,
                      ).copyWith(color: AppColors.slate),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (widget.controller.running) ...[
          _RunningCard(
            completed: widget.controller.completed,
            total: widget.controller.total,
            onCancel: widget.controller.cancel,
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            const Icon(
              Icons.save_outlined,
              size: 15,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '进度保存在本机。重新打开 App 后，连接原飞书账号即可恢复未完成文档。',
                style: AppTextStyles.labelSmall(
                  context,
                ).copyWith(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder(
          future: jobs,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppEmptyState(
                icon: Icons.cloud_off_rounded,
                accent: AppColors.error,
                title: '读取失败',
                description: '${snapshot.error}',
                actionLabel: '重试',
                onAction: _refresh,
              );
            }
            if (!snapshot.hasData) {
              return const AppLoadingState(label: '正在读取任务…');
            }
            if (snapshot.data!.isEmpty) {
              return const AppEmptyState(
                icon: Icons.cloud_sync_outlined,
                title: '暂时没有导入任务',
                description: '从飞书选择资料并开始导入后，任务进度会显示在这里。',
              );
            }
            return Column(
              children: [
                for (final job in snapshot.data!)
                  _JobCard(
                    job: job,
                    running: widget.controller.running,
                    failedItems: widget.controller.database.database.then(
                      (db) => db.query(
                        'feishu_import_job_items',
                        where: "job_id=? AND status='failed'",
                        whereArgs: [job['id']],
                      ),
                    ),
                    onResume: () => _resume(job['id'] as int),
                    onRescan: () => _rescan(job),
                    onCancelWaiting: () => _cancelWaiting(job),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  /// Re-open the confirmation page for a job that has not finished, replacing
  /// the old plan with a fresh scan.
  Future<void> _rescan(Map<String, Object?> job) async {
    final plan = jsonDecode(job['plan_json'] as String) as Map<String, dynamic>;
    final roots = (plan['roots'] as List)
        .map(
          (r) => <String, dynamic>{
            'kind': r['kind'],
            'id': r['id'],
            'space_id': r['space_id'] ?? '',
            'excluded': r['excluded'] ?? [],
            'included': r['included'] ?? [],
          },
        )
        .toList();
    if (!widget.controller.connected) {
      if (mounted) showAppToast(context, '请先连接原飞书账号');
      return;
    }
    if (widget.controller.connection?['account_id'] != job['account_id']) {
      if (mounted) showAppToast(context, '请连接该任务原来的飞书账号');
      return;
    }
    await _markCancelled(job);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeishuImportConfirmPage(
          controller: widget.controller,
          roots: roots,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _cancelWaiting(Map<String, Object?> job) async {
    await _markCancelled(job);
    _refresh();
  }

  Future<void> _markCancelled(Map<String, Object?> job) async {
    final db = await widget.controller.database.database;
    await db.update(
      'feishu_import_jobs',
      {'status': 'cancelled'},
      where: 'id=? AND user_id=?',
      whereArgs: [job['id'], widget.controller.userId],
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({
    required this.completed,
    required this.total,
    required this.onCancel,
  });

  final int completed;
  final int total;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.tintOf(AppColors.primary, 0.10),
          AppColors.tintOf(AppColors.accentSky, 0.10),
        ],
      ),
      borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      border: Border.all(color: AppColors.tintOf(AppColors.primary, 0.18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '正在导入',
                style: AppTextStyles.title(context),
              ),
            ),
            Text(
              // Keep the historic "0/1 篇" shape: the controller test and the
              // import page both read it.
              total == 0 ? '准备中' : '$completed/$total 篇',
              style: AppTextStyles.label(
                context,
              ).copyWith(color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppProgressBar(value: total == 0 ? 0 : completed / total),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onCancel,
            child: const Text('取消任务（保留已完成部分）'),
          ),
        ),
      ],
    ),
  );
}

/// One import job: status, progress, failed items, and the actions that apply
/// to that status. Keeps the three recovery actions from floating loose.
class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.running,
    required this.failedItems,
    required this.onResume,
    required this.onRescan,
    required this.onCancelWaiting,
  });

  final Map<String, Object?> job;
  final bool running;
  final Future<List<Map<String, Object?>>> failedItems;
  final VoidCallback onResume;
  final VoidCallback onRescan;
  final VoidCallback onCancelWaiting;

  static const _statusLabels = {
    'queued': '待执行',
    'running': '导入中',
    'paused': '待恢复',
    'cancelled': '已取消',
    'partial': '部分成功',
    'done': '已完成',
    'failed': '失败',
  };

  Color get _accent => switch (job['status']) {
    'done' => AppColors.success,
    'partial' => AppColors.accentAmber,
    'failed' => AppColors.error,
    'running' => AppColors.primary,
    'cancelled' => AppColors.textTertiary,
    _ => AppColors.accentSky,
  };

  @override
  Widget build(BuildContext context) {
    final completed = (job['completed'] as num?)?.toInt() ?? 0;
    final total = (job['total'] as num?)?.toInt() ?? 0;
    final ratio = total == 0 ? 0.0 : completed / total;
    final canAct = !running && job['status'] != 'done';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard.outlined(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '任务 ${job['id']}',
                  style: AppTextStyles.title(context),
                ),
                const Spacer(),
                AppTag(
                  label: _statusLabels[job['status']] ?? '未知状态',
                  accent: _accent,
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppProgressBar(
              value: ratio,
              accent: _accent,
              height: 6,
            ),
            const SizedBox(height: 6),
            Text(
              '成功 $completed / $total 篇',
              style: AppTextStyles.caption(
                context,
              ).copyWith(color: AppColors.textSecondary),
            ),
            if (job['error'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${job['error']}',
                  style: AppTextStyles.caption(
                    context,
                  ).copyWith(color: AppColors.error),
                ),
              ),
            FutureBuilder(
              future: failedItems,
              builder: (context, errors) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final error in errors.data ?? <Map<String, Object?>>[])
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${error['document_id']}：${error['error']}',
                        style: AppTextStyles.caption(context),
                      ),
                    ),
                ],
              ),
            ),
            if (canAct)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: onResume,
                      child: const Text('恢复 / 重试未完成文档'),
                    ),
                    TextButton(
                      onPressed: onRescan,
                      child: const Text('重新扫描（替换此任务）'),
                    ),
                    TextButton(
                      onPressed: onCancelWaiting,
                      child: const Text('取消等待'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
