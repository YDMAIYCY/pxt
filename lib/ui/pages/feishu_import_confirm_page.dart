import 'package:flutter/material.dart';
import 'dart:convert';
import '../../feishu/feishu_client.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/models/knowledge_library_record.dart';
import '../../feishu/feishu_controller.dart';
import '../theme/app_theme.dart';
import 'feishu_job_page.dart';

class FeishuImportConfirmPage extends StatefulWidget {
  const FeishuImportConfirmPage({
    required this.controller,
    this.roots,
    this.plan,
    super.key,
  });
  final FeishuController controller;
  final List<Map<String, dynamic>>? roots;
  final Map<String, dynamic>? plan;
  @override
  State<FeishuImportConfirmPage> createState() =>
      _FeishuImportConfirmPageState();
}

class _FeishuImportConfirmPageState extends State<FeishuImportConfirmPage> {
  Map<String, dynamic>? plan;
  String? error;
  int mode = 1, imported = 0, newLibraries = 0, updatingLibraries = 0;
  bool starting = false, createNew = false;
  List<KnowledgeLibraryRecord> libraries = [];
  int? target;
  final name = TextEditingController(), description = TextEditingController();
  Future<void> _recount() async {
    if (plan == null) return;
    final copy = <String, dynamic>{
      ...plan!,
      'roots': [
        for (final root in plan!['roots'] as List)
          <String, dynamic>{
            ...root as Map<String, dynamic>,
            if (root['kind'] == 'docx') 'target_library_id': target,
          },
      ],
    };
    final count = await widget.controller.repository.alreadyImported(
      widget.controller.userId,
      copy,
    );
    if (mounted) setState(() => imported = count);
  }

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      plan = null;
      error = null;
    });
    try {
      final value =
          widget.plan ??
          await widget.controller.client.request(
            'POST',
            '/imports/scan',
            body: {'roots': widget.roots},
          );
      final books = await KnowledgeLibraryRepository(
        database: widget.controller.database,
      ).fetchLibraries(widget.controller.userId);
      final count = await widget.controller.repository.alreadyImported(
        widget.controller.userId,
        value,
      );
      final db = await widget.controller.database.database;
      var creating = 0, updating = 0;
      for (final root in value['roots'] as List) {
        if (root['kind'] == 'docx') continue;
        final existing = await db.query(
          'feishu_containers',
          where: 'user_id=? AND container_type=? AND container_id=?',
          whereArgs: [widget.controller.userId, root['kind'], root['id']],
        );
        existing.isEmpty ? creating++ : updating++;
      }
      if (mounted) {
        setState(() {
          plan = value;
          imported = count;
          libraries = books;
          newLibraries = creating;
          updatingLibraries = updating;
        });
      }
    } catch (failure) {
      if (failure is FeishuException && failure.statusCode == 401) {
        await widget.controller.expire();
      }
      if (mounted) setState(() => error = '$failure');
    }
  }

  Future<void> _start() async {
    if (starting || plan == null) return;
    setState(() => starting = true);
    try {
      final submission = jsonDecode(jsonEncode(plan)) as Map<String, dynamic>;
      for (final root in submission['roots'] as List) {
        root['sync_mode'] = mode;
        if (root['kind'] == 'docx' && root['target_library_id'] == null) {
          root['target_library_id'] = createNew ? null : target;
        }
      }
      if (createNew) {
        submission['new_library'] = {
          'name': name.text.trim(),
          'description': description.text.trim(),
        };
      }
      await widget.controller.importPlan(submission, mode);
      if (mounted) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FeishuJobPage(controller: widget.controller),
          ),
        );
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = '$failure';
          starting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roots = (plan?['roots'] as List?) ?? [];
    final loose = roots.any(
      (r) => r['kind'] == 'docx' && r['target_library_id'] == null,
    );
    final count = roots.fold<int>(
      0,
      (n, r) => n + (r['documents'] as List).length,
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(title: const Text('确认导入')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed:
                plan == null ||
                    starting ||
                    roots.isEmpty ||
                    (loose &&
                        target == null &&
                        (!createNew || name.text.trim().isEmpty))
                ? null
                : _start,
            child: Text(starting ? '正在创建任务…' : '开始导入 $count 篇文档'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (plan == null && error == null) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            const Text('正在递归扫描真实资源，数量尚未确定。可返回取消确认。'),
          ],
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: AppColors.error)),
            TextButton(onPressed: _scan, child: const Text('重新扫描')),
          ],
          if (plan != null) ...[
            Text(
              plan!['scan_complete'] == true
                  ? '资源扫描完成'
                  : '扫描部分失败：已发现数量不是完整目录总量',
              style: AppTextStyles.h3(context),
            ),
            const SizedBox(height: 10),
            Text(
              '发现受支持文档 $count 篇 · 已导入 $imported 篇\n无法读取资源 ${(plan!['errors'] as List).length} 项\n创建 ${newLibraries + (loose && createNew ? 1 : 0)} 个知识库 · 更新 ${updatingLibraries + (loose && target != null ? 1 : 0)} 个知识库\n正文访问权将在逐篇读取时验证',
            ),
            if ((plan!['covered_selections'] as List).isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('被父级覆盖的文件夹和文档已合并，避免重复导入。'),
              ),
            for (final root in roots)
              Card(
                child: ExpansionTile(
                  title: Text(root['name'] as String),
                  subtitle: Text('${(root['documents'] as List).length} 篇文档'),
                  children: [
                    for (final doc in root['documents'] as List)
                      ListTile(
                        title: Text(doc['title'] as String),
                        subtitle: Text(doc['relative_path'] as String),
                      ),
                  ],
                ),
              ),
            for (final failure in plan!['errors'] as List)
              Text(
                '${failure['path'] ?? failure['resource_id'] ?? failure['root_id']}：${failure['detail']['message']}',
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            if (loose) ...[
              const SizedBox(height: 16),
              Text('单篇文档保存到', style: AppTextStyles.h3(context)),
              DropdownButtonFormField<int>(
                initialValue: target,
                isExpanded: true,
                hint: const Text('请选择已有知识库'),
                items: libraries
                    .map(
                      (l) => DropdownMenuItem(
                        value: l.id,
                        child: Text(l.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  target = v;
                  createNew = false;
                  _recount();
                }),
              ),
              CheckboxListTile(
                title: const Text('创建一个知识库保存这些单篇文档'),
                value: createNew,
                onChanged: (v) => setState(() {
                  createNew = v == true;
                  if (createNew) target = null;
                  _recount();
                }),
              ),
              if (createNew) ...[
                TextField(
                  controller: name,
                  onChanged: (_) => setState(() {}),
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: '知识库名称'),
                ),
                TextField(
                  controller: description,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '简介（可选）'),
                ),
              ],
            ],
            const SizedBox(height: 16),
            Text('导入模式', style: AppTextStyles.h3(context)),
            for (final entry in const [
              (0, '仅导入一次'),
              (1, '持续同步已有文档'),
              (2, '持续同步并纳入后续新增文档'),
            ])
              ListTile(
                title: Text(entry.$2),
                leading: Icon(
                  mode == entry.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: AppColors.primary,
                ),
                onTap: () => setState(() => mode = entry.$1),
              ),
            const Text(
              '同步范围将保存在本机，需在 App 内点击同步更新。App 关闭后服务器不会持续导入。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
