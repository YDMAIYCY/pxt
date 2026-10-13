import 'package:flutter/material.dart';
import '../../database/import_record_repository.dart';
import '../../database/models/import_record.dart';
import '../theme/app_theme.dart';

const knowledgeOutcomes = [
  (
    type: 'ocr',
    title: '原始资料 / OCR 文本',
    description: '查看原始资料与识别的\n完整文本内容',
    color: 0xFF5B8CFF,
    icon: Icons.description_outlined,
    unit: '页内容',
  ),
  (
    type: 'knowledge_cards',
    title: '知识卡片',
    description: '提炼核心知识点，\n便于记忆复习',
    color: 0xFFF5B632,
    icon: Icons.style_outlined,
    unit: '张卡片',
  ),
  (
    type: 'review_outlines',
    title: '复习提纲',
    description: '梳理知识框架\n与重点总结',
    color: 0xFFFF8580,
    icon: Icons.article_outlined,
    unit: '份提纲',
  ),
  (
    type: 'mindmap_texts',
    title: '思维导图',
    description: '呈现知识结构\n与逻辑关系',
    color: 0xFF9A72EF,
    icon: Icons.account_tree_outlined,
    unit: '张导图',
  ),
  (
    type: 'practice_questions',
    title: '练习题',
    description: '基于本次资料生成的\n典型练习题',
    color: 0xFF39BF9B,
    icon: Icons.edit_outlined,
    unit: '道练习题',
  ),
  (
    type: 'wrong_questions',
    title: '错题解析',
    description: '收录练习中的易错题\n并提供详细解析',
    color: 0xFFF37DA4,
    icon: Icons.assignment_late_outlined,
    unit: '道错题',
  ),
];

class OutcomeTile extends StatelessWidget {
  const OutcomeTile({
    required this.title,
    required this.description,
    required this.color,
    required this.icon,
    required this.countLabel,
    required this.onTap,
    super.key,
  });
  final String title, description, countLabel;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Color.lerp(color, Colors.white, .93),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: .5),
              color.withValues(alpha: .04),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right,
                  size: 19,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: Color(0xFF7B8CA6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              countLabel,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF516484),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class OutcomeSearch extends StatelessWidget {
  const OutcomeSearch({
    super.key,
    required this.record,
    required this.repository,
    required this.query,
    required this.onOpen,
  });
  final ImportRecord record;
  final ImportRecordRepository repository;
  final String query;
  final void Function(String, String) onOpen;
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: Future.wait(
      knowledgeOutcomes
          .where((i) => i.type != 'ocr')
          .map(
            (i) async => (
              item: i,
              rows: await repository.results(
                record.userId,
                record.id,
                i.type,
                query: query,
              ),
            ),
          ),
    ),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text('搜索失败：${snapshot.error}');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final matches = snapshot.data!.where((r) => r.rows.isNotEmpty).toList();
      if (matches.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Text('本次记录中没有匹配的成果内容。'),
        );
      }
      return Column(
        children: matches
            .map(
              (r) => ListTile(
                dense: true,
                title: Text('${r.item.title} · ${r.rows.length} 条匹配'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(r.item.type, r.item.title),
              ),
            )
            .toList(),
      );
    },
  );
}
