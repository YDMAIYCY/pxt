import 'package:flutter/material.dart';

class KnowledgeTabPage extends StatelessWidget {
  const KnowledgeTabPage({super.key});

  static const List<_KnowledgeTypeItem> _typeItems = [
    _KnowledgeTypeItem(
      title: '讲义资料',
      subtitle: '按课程查看拍照与导入内容',
      icon: Icons.menu_book_rounded,
      color: Color(0xFFE0F2FE),
    ),
    _KnowledgeTypeItem(
      title: '知识卡片',
      subtitle: '概念、定义、公式快速复习',
      icon: Icons.style_rounded,
      color: Color(0xFFF0FDF4),
    ),
    _KnowledgeTypeItem(
      title: '复习提纲',
      subtitle: '按章节整理重点与脉络',
      icon: Icons.list_alt_rounded,
      color: Color(0xFFFFF7ED),
    ),
    _KnowledgeTypeItem(
      title: '思维导图文字版',
      subtitle: '结构化拆解知识点关系',
      icon: Icons.account_tree_rounded,
      color: Color(0xFFF5F3FF),
    ),
    _KnowledgeTypeItem(
      title: '复习题',
      subtitle: '练习题集合与训练记录',
      icon: Icons.quiz_rounded,
      color: Color(0xFFFDF2F8),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 14),
                _buildTypeGrid(context),
                const SizedBox(height: 14),
                _buildRecentKnowledgeSection(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFECFEFF), Color(0xFFEEF2FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.collections_bookmark_rounded,
              color: Color(0xFF0C4A6E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '知识库',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0B1324),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '统一查看讲义、卡片、提纲、导图和复习题',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeGrid(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '内容分类',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0B1324),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _typeItems
                    .map(
                      (item) => SizedBox(
                        width: itemWidth,
                        child: _KnowledgeTypeCard(item: item),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecentKnowledgeSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近保存',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0B1324),
            ),
          ),
          const SizedBox(height: 10),
          ...const [
            _RecentKnowledgeTile(
              title: '函数极限复习提纲',
              subtitle: '数学 / 提纲 / 2 小时前',
            ),
            _RecentKnowledgeTile(title: '电磁感应知识卡片集', subtitle: '物理 / 卡片 / 今天'),
            _RecentKnowledgeTile(
              title: 'Unit 4 词汇复习题',
              subtitle: '英语 / 复习题 / 昨天',
            ),
          ],
        ],
      ),
    );
  }
}

class _KnowledgeTypeCard extends StatelessWidget {
  const _KnowledgeTypeCard({required this.item});

  final _KnowledgeTypeItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: item.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: const Color(0xFF0C4A6E)),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xFF0B1324),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentKnowledgeTile extends StatelessWidget {
  const _RecentKnowledgeTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, color: Color(0xFF0C4A6E)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF0B1324),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }
}

class _KnowledgeTypeItem {
  const _KnowledgeTypeItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}
