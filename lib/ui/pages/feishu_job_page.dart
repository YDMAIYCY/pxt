import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../feishu/feishu_controller.dart';
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
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.controller.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(widget.controller.message),
          ),
        if (widget.controller.running) ...[
          LinearProgressIndicator(
            value: widget.controller.total == 0
                ? null
                : widget.controller.completed / widget.controller.total,
          ),
          Text(
            widget.controller.total == 0
                ? '正在准备任务…'
                : '${widget.controller.completed}/${widget.controller.total} 篇',
          ),
          TextButton(
            onPressed: widget.controller.cancel,
            child: const Text('取消任务（保留已完成部分）'),
          ),
        ],
        const Text('进度保存在本机。重新打开 App 后，连接原飞书账号即可恢复未完成文档。'),
        FutureBuilder(
          future: jobs,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('读取失败：${snapshot.error}');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return Column(
              children: [
                for (final job in snapshot.data!)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '任务 ${job['id']} · ${{'queued': '待执行', 'running': '导入中', 'paused': '待恢复', 'cancelled': '已取消', 'partial': '部分成功', 'done': '已完成', 'failed': '失败'}[job['status']]}',
                          ),
                          Text('成功 ${job['completed']} / ${job['total']} 篇'),
                          if (job['error'] != null) Text('${job['error']}'),
                          if (!widget.controller.running &&
                              job['status'] != 'done')
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: () => _resume(job['id'] as int),
                                  child: const Text('恢复 / 重试未完成文档'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final plan =
                                        jsonDecode(job['plan_json'] as String)
                                            as Map<String, dynamic>;
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
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('请先连接原飞书账号'),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    if (widget
                                            .controller
                                            .connection?['account_id'] !=
                                        job['account_id']) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('请连接该任务原来的飞书账号'),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    final db = await widget
                                        .controller
                                        .database
                                        .database;
                                    await db.update(
                                      'feishu_import_jobs',
                                      {'status': 'cancelled'},
                                      where: 'id=? AND user_id=?',
                                      whereArgs: [
                                        job['id'],
                                        widget.controller.userId,
                                      ],
                                    );
                                    if (!context.mounted) return;
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
                                  },
                                  child: const Text('重新扫描（替换此任务）'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final db = await widget
                                        .controller
                                        .database
                                        .database;
                                    await db.update(
                                      'feishu_import_jobs',
                                      {'status': 'cancelled'},
                                      where: 'id=? AND user_id=?',
                                      whereArgs: [
                                        job['id'],
                                        widget.controller.userId,
                                      ],
                                    );
                                    _refresh();
                                  },
                                  child: const Text('取消等待'),
                                ),
                              ],
                            ),
                          FutureBuilder(
                            future: widget.controller.database.database.then(
                              (db) => db.query(
                                'feishu_import_job_items',
                                where: "job_id=? AND status='failed'",
                                whereArgs: [job['id']],
                              ),
                            ),
                            builder: (context, errors) => Column(
                              children: [
                                for (final error
                                    in errors.data ?? <Map<String, Object?>>[])
                                  Text(
                                    '${error['document_id']}：${error['error']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
