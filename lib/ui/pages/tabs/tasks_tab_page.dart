import 'package:flutter/material.dart';

class TasksTabPage extends StatelessWidget {
  const TasksTabPage({super.key});

  static const List<_TaskBoardItem> _taskBoardItems = [
    _TaskBoardItem(
      title: '待生成 AI 内容',
      value: '4',
      icon: Icons.hourglass_top_rounded,
      color: Color(0xFFFFF7ED),
    ),
    _TaskBoardItem(
      title: '待处理错题',
      value: '7',
      icon: Icons.report_problem_rounded,
      color: Color(0xFFFEF2F2),
    ),
    _TaskBoardItem(
      title: '今日完成任务',
      value: '6',
      icon: Icons.check_circle_rounded,
      color: Color(0xFFF0FDF4),
    ),
    _TaskBoardItem(
      title: '进行中流程',
      value: '2',
      icon: Icons.auto_mode_rounded,
      color: Color(0xFFEFF6FF),
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
                _buildTaskBoard(context),
                const SizedBox(height: 14),
                _buildWrongQuestionSection(context),
                const SizedBox(height: 14),
                _buildAiTaskSection(context),
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
          colors: [Color(0xFFFEF2F2), Color(0xFFFFFBEB)],
        ),
        borderRadius: BorderRadius.circular(24),
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
              Icons.fact_check_rounded,
              color: Color(0xFF9A3412),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '错题 / 任务',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0B1324),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '集中管理待处理内容与 AI 生成记录',
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

  Widget _buildTaskBoard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 12) / 2;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _taskBoardItems
                .map(
                  (item) => SizedBox(
                    width: itemWidth,
                    child: _TaskBoardCard(item: item),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildWrongQuestionSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '错题讲解记录',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0B1324),
            ),
          ),
          const SizedBox(height: 10),
          ...const [
            _TaskListTile(
              title: '导数应用题：最值判断失误',
              subtitle: '生成于 今天 10:12',
              status: '待复习',
            ),
            _TaskListTile(
              title: '电路分析：符号方向混淆',
              subtitle: '生成于 昨天 21:16',
              status: '已讲解',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiTaskSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 生成任务',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0B1324),
            ),
          ),
          const SizedBox(height: 10),
          ...const [
            _TaskListTile(
              title: '函数极限课件 -> 生成复习题',
              subtitle: 'OCR 完成，等待生成',
              status: '进行中',
            ),
            _TaskListTile(
              title: '英语讲义 -> 生成知识卡片',
              subtitle: '任务创建于 09:50',
              status: '排队中',
            ),
            _TaskListTile(
              title: '有机化学错题 -> 讲解重写',
              subtitle: '任务创建于 昨天',
              status: '待处理',
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskBoardCard extends StatelessWidget {
  const _TaskBoardCard({required this.item});

  final _TaskBoardItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: item.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: const Color(0xFF9A3412)),
          const SizedBox(height: 8),
          Text(
            item.value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF7C2D12),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF7C2D12),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskListTile extends StatelessWidget {
  const _TaskListTile({
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String title;
  final String subtitle;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
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
                const SizedBox(height: 4),
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
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDD5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskBoardItem {
  const _TaskBoardItem({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
}
