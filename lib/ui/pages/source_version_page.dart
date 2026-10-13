import 'dart:convert';
import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../theme/app_theme.dart';

class SourceVersionPage extends StatelessWidget {
  const SourceVersionPage({required this.userId, required this.versionId,
    this.database, super.key});
  final int userId;
  final int versionId;
  final AppDatabase? database;
  Future<Map<String, Object?>> _load() async {
    final db = await (database ?? AppDatabase.instance).database;
    final rows = await db.rawQuery('''SELECT v.* FROM record_source_versions v
      JOIN import_records r ON r.id = v.record_id WHERE v.id = ? AND r.user_id = ?''',
      [versionId, userId]);
    if (rows.isEmpty) throw StateError('来源版本不存在或无权访问');
    return rows.single;
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('生成当时的来源')),
    body: FutureBuilder<Map<String, Object?>>(future: _load(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final row = snapshot.data!;
        final data = jsonDecode(row['content'] as String) as Map;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('来源快照 #$versionId · ${row['created_at']}',
            style: AppTextStyles.caption(context)),
          const SizedBox(height: 12),
          const Text('保存的是生成或作答当时的内容，后续校正不会覆盖这份依据。'),
          const SizedBox(height: 12),
          for (final item in data['sources'] as List)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item['title']}${item['page'] == null ? '' : ' · 第 ${item['page']} 页'}',
                  style: AppTextStyles.h3(context)),
                const SizedBox(height: 8),
                SelectableText('${item['text']}'),
                if (item['image_understanding'] != null)
                  SelectableText('图片理解（含不确定性）：${item['image_understanding']}'),
              ]))),
        ]);
      }),
  );
}
