import 'package:flutter/material.dart';

import '../../../common/app_assets.dart';

class HomeTabPage extends StatelessWidget {
  const HomeTabPage({super.key});

  static const List<_RecentRecord> _recentRecords = [
    _RecentRecord(
      title: '高数第5章课后题（函数极限）',
      sourceType: '题目',
      createdAt: '今天 09:35',
      ocrDone: true,
      aiDone: true,
    ),
    _RecentRecord(
      title: '大学物理讲义：电磁感应重点段落',
      sourceType: '讲义',
      createdAt: '今天 08:10',
      ocrDone: true,
      aiDone: false,
    ),
    _RecentRecord(
      title: '英语阅读课件 Unit 4',
      sourceType: '课件',
      createdAt: '昨天 21:48',
      ocrDone: true,
      aiDone: true,
    ),
    _RecentRecord(
      title: '有机化学错题页（醇醚部分）',
      sourceType: '题目',
      createdAt: '昨天 19:26',
      ocrDone: false,
      aiDone: false,
    ),
  ];

  static const List<_AiResultItem> _aiResults = [
    _AiResultItem(
      type: '知识卡片',
      title: '电磁感应核心公式卡',
      summary: '提炼 6 个高频考点 + 典型陷阱',
      createdAt: '今天 09:42',
      accentColor: Color(0xFF0EA5E9),
    ),
    _AiResultItem(
      type: '复习提纲',
      title: '函数极限冲刺提纲',
      summary: '按定义、判别、题型三层组织复习顺序',
      createdAt: '今天 09:40',
      accentColor: Color(0xFF16A34A),
    ),
    _AiResultItem(
      type: '思维导图文字版',
      title: 'Unit 4 阅读结构图',
      summary: '主线观点 + 分论据 + 关键词联想',
      createdAt: '昨天 21:55',
      accentColor: Color(0xFF2563EB),
    ),
    _AiResultItem(
      type: '错题讲解',
      title: '醇醚反应路径纠错',
      summary: '定位 3 处常见失分点与替代解法',
      createdAt: '昨天 19:38',
      accentColor: Color(0xFFEA580C),
    ),
    _AiResultItem(
      type: '复习题',
      title: '电磁感应自测 10 题',
      summary: '由浅入深，覆盖概念到综合应用',
      createdAt: '昨天 18:20',
      accentColor: Color(0xFF7C3AED),
    ),
  ];

  static const List<_StudyStat> _studyStats = [
    _StudyStat(label: '今日拍照次数', value: '8'),
    _StudyStat(label: '今日识别字数', value: '4,360'),
    _StudyStat(label: '今日新增知识卡片', value: '6'),
    _StudyStat(label: '今日复习题生成数', value: '12'),
    _StudyStat(label: '今日错题讲解数', value: '5'),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 58),
                child: Opacity(
                  opacity: 0.8,
                  child: Image.asset(
                    AppAssets.homeBackdropImage,
                    fit: BoxFit.cover,
                    width: MediaQuery.sizeOf(context).width,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeSection(context),
                    const SizedBox(height: 14),
                    _buildQuickActionsSection(context),
                    const SizedBox(height: 14),
                    _buildRecentRecordsSection(),
                    const SizedBox(height: 14),
                    _buildAiResultSection(),
                    const SizedBox(height: 14),
                    _buildStatsSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWelcomeSection(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _SoftSection(
      backgroundColor: const Color(0xFFEFF6FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF1E293B,
                            ).withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        AppAssets.logoIcon,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.auto_stories_rounded,
                              size: 34,
                              color: Color(0xFF0C4A6E),
                            ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '你好，今天也来高效学习吧',
                      style: textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF1E3A8A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '拍一拍，立刻生成复习资料',
                      style: textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  tooltip: '设置',
                  onPressed: () {},
                  icon: const Icon(Icons.tune_rounded),
                  color: const Color(0xFF0C4A6E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    size: 16,
                    color: Color(0xFFEA580C),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '今日已整理 3 份资料，继续保持学习节奏',
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    return _SoftSection(
      backgroundColor: const Color(0xFFECFDF5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.flash_on_rounded, title: '快捷入口'),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0EA5E9), Color(0xFF0C4A6E)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0C4A6E).withValues(alpha: 0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(18, 16, 16, 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.camera_alt_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '拍照识别题目 / 讲义 / 课件',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 12) / 2;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    const [
                          _QuickActionTile(
                            width: null,
                            icon: Icons.image_rounded,
                            title: '导入图片',
                            color: Color(0xFFE0F2FE),
                          ),
                          _QuickActionTile(
                            width: null,
                            icon: Icons.description_rounded,
                            title: '导入讲义/课件',
                            color: Color(0xFFFFF7ED),
                          ),
                          _QuickActionTile(
                            width: null,
                            icon: Icons.auto_awesome_rounded,
                            title: 'AI生成',
                            color: Color(0xFFF5F3FF),
                          ),
                        ]
                        .map((tile) => SizedBox(width: itemWidth, child: tile))
                        .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRecordsSection() {
    return _SoftSection(
      backgroundColor: const Color(0xFFF0FDF4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.history_edu_rounded,
            title: '最近处理记录',
          ),
          const SizedBox(height: 12),
          ..._recentRecords.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecentRecordCard(record: record),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiResultSection() {
    return _SoftSection(
      backgroundColor: const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.psychology_alt_rounded,
            title: 'AI 学习成果区',
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _aiResults.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                return _AiResultCard(item: _aiResults[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return _SoftSection(
      backgroundColor: const Color(0xFFFFFBEB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.insights_rounded, title: '学习统计区'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 560 ? 3 : 2;
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _studyStats
                    .map(
                      (stat) => SizedBox(
                        width: itemWidth,
                        child: _StatCard(stat: stat),
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: const Color(0xFF0C4A6E)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0B1324),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SoftSection extends StatelessWidget {
  const _SoftSection({required this.child, required this.backgroundColor});

  final Widget child;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.80)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.color,
    this.width,
  });

  final double? width;
  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white),
          ),
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: const Color(0xFF0C4A6E)),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0B1324),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRecordCard extends StatelessWidget {
  const _RecentRecordCard({required this.record});

  final _RecentRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1FAE5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF0B1324),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  record.sourceType,
                  style: const TextStyle(
                    color: Color(0xFF0C4A6E),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            record.createdAt,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatusTag(
                label: record.ocrDone ? 'OCR 已完成' : 'OCR 处理中',
                done: record.ocrDone,
              ),
              const SizedBox(width: 8),
              _StatusTag(
                label: record.aiDone ? 'AI 已生成' : 'AI 待生成',
                done: record.aiDone,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final doneColor = done ? const Color(0xFF166534) : const Color(0xFF9A3412);
    final doneBackground = done
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFFEDD5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: doneBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: doneColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AiResultCard extends StatelessWidget {
  const _AiResultCard({required this.item});

  final _AiResultItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 218,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: item.accentColor.withValues(alpha: 0.20),
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: item.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item.type,
                style: TextStyle(
                  color: item.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFF0B1324),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                item.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.createdAt,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});

  final _StudyStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFEDD5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF9A3412),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF7C2D12),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRecord {
  const _RecentRecord({
    required this.title,
    required this.sourceType,
    required this.createdAt,
    required this.ocrDone,
    required this.aiDone,
  });

  final String title;
  final String sourceType;
  final String createdAt;
  final bool ocrDone;
  final bool aiDone;
}

class _AiResultItem {
  const _AiResultItem({
    required this.type,
    required this.title,
    required this.summary,
    required this.createdAt,
    required this.accentColor,
  });

  final String type;
  final String title;
  final String summary;
  final String createdAt;
  final Color accentColor;
}

class _StudyStat {
  const _StudyStat({required this.label, required this.value});

  final String label;
  final String value;
}
