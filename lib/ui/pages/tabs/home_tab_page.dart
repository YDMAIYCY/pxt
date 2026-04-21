import 'dart:io';

import 'package:flutter/material.dart';

import '../../../camera/document_input_contract.dart';
import '../../../common/app_assets.dart';
import '../../../database/auth_repository.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/models/user_profile.dart';
import '../../../database/source_document_repository.dart';
import '../../../pipeline/document_ingest_service.dart';
import '../document_detail_page.dart';

// ========== 首页页面 ==========
// 承接第七阶段主流程：拍照/相册导入、最近资料记录展示、跳转资料详情页。

class HomeTabPage extends StatefulWidget {
  const HomeTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.documentIngestService,
    this.detailPageBuilder,
    super.key,
  });

  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final DocumentIngestService? documentIngestService;
  final Widget Function(int documentId)? detailPageBuilder;

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final DocumentIngestService _documentIngestService;

  late Future<_HomeTabViewData> _viewDataFuture;
  bool _isImporting = false;

  static const List<_AiResultItem> _aiResults = [
    _AiResultItem(
      type: '知识卡片',
      title: '第八阶段接入真实卡片结果',
      summary: '当前区域先保留为展示占位，后续会改成读取数据库中的 AI 生成内容。',
      createdAt: '后续阶段',
      accentColor: Color(0xFF0EA5E9),
    ),
    _AiResultItem(
      type: '复习提纲',
      title: '第九阶段接入真实提纲结果',
      summary: '完成 OCR 和 LLM 后，这里会显示每条资料对应的生成内容。',
      createdAt: '后续阶段',
      accentColor: Color(0xFF16A34A),
    ),
    _AiResultItem(
      type: '思维导图文字版',
      title: '第九阶段接入真实导图结果',
      summary: '当前先保留首页结构，避免提前侵入 OCR/AI 阶段的业务实现。',
      createdAt: '后续阶段',
      accentColor: Color(0xFF2563EB),
    ),
  ];

  static const List<_StudyStat> _studyStats = [
    _StudyStat(label: '今日拍照次数', value: '--'),
    _StudyStat(label: '今日识别字数', value: '--'),
    _StudyStat(label: '知识卡片数量', value: '--'),
    _StudyStat(label: '复习题生成数', value: '--'),
  ];

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _documentIngestService =
        widget.documentIngestService ?? DocumentIngestService();
    _viewDataFuture = _loadViewData();
  }

  // ========== 数据读取 ==========
  // 读取当前登录用户与首页最近资料记录，驱动首页真实内容展示。

  Future<_HomeTabViewData> _loadViewData() async {
    await _authRepository.ensureInitialized();
    final currentUser = await _authRepository.getCurrentUserProfile();

    if (currentUser == null) {
      throw StateError('当前登录状态已失效');
    }

    final recentDocuments = await _sourceDocumentRepository
        .fetchRecentSourceDocuments(userId: currentUser.id);

    return _HomeTabViewData(
      currentUser: currentUser,
      recentDocuments: recentDocuments,
    );
  }

  Future<void> _refreshViewData() async {
    final future = _loadViewData();
    setState(() {
      _viewDataFuture = future;
    });
    await future;
  }

  // ========== 导入流程 ==========
  // 处理拍照与相册导入，成功后跳转资料详情页，并刷新首页最近记录。

  Future<void> _handleImageImport(ImageInputSource source) async {
    if (_isImporting) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final currentUser = await _authRepository.getCurrentUserProfile();
      if (currentUser == null) {
        if (!mounted) {
          return;
        }
        _showMessage('登录状态已失效，请重新登录后再试');
        return;
      }

      final createdDocument = await _documentIngestService.importFromInput(
        userId: currentUser.id,
        source: source,
      );

      if (!mounted || createdDocument == null) {
        return;
      }

      await _openDocumentDetailById(createdDocument.id);

      if (!mounted) {
        return;
      }

      try {
        await _refreshViewData();
      } catch (_) {
        if (mounted) {
          _showMessage('资料已保存成功，但首页刷新失败，请下拉刷新重试');
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('导入失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _openDocumentDetail(SourceDocumentRecord document) {
    return _openDocumentDetailById(document.id);
  }

  Future<void> _openDocumentDetailById(int documentId) {
    final detailPage =
        widget.detailPageBuilder?.call(documentId) ??
        DocumentDetailPage(documentId: documentId);

    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => detailPage,
      ),
    );
  }

  void _showComingSoon(String featureName) {
    _showMessage('$featureName会在后续阶段接入，这一阶段先完成图片导入闭环');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ========== 页面构建 ==========
  // 首页保留既有视觉框架，但将第七阶段相关模块替换为真实业务能力。

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
        FutureBuilder<_HomeTabViewData>(
          future: _viewDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError && snapshot.data == null) {
              return _HomeStatePanel(
                icon: Icons.error_outline_rounded,
                title: '首页加载失败',
                description: '请稍后重试，或重新登录后再查看首页内容。',
                actionLabel: '重新加载',
                onPressed: _refreshViewData,
              );
            }

            final viewData = snapshot.data!;

            return RefreshIndicator(
              onRefresh: _refreshViewData,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWelcomeSection(
                            context,
                            viewData.currentUser,
                            viewData.recentDocuments.length,
                          ),
                          const SizedBox(height: 14),
                          _buildQuickActionsSection(),
                          const SizedBox(height: 14),
                          _buildRecentRecordsSection(viewData.recentDocuments),
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
            );
          },
        ),
      ],
    );
  }

  Widget _buildWelcomeSection(
    BuildContext context,
    UserProfile user,
    int recentCount,
  ) {
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
                      '你好，${user.primaryName}',
                      style: textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF1E3A8A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '第七阶段已接通图片导入闭环，拍一拍就能把资料保存进本地知识库',
                      style: textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w500,
                        height: 1.45,
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
                  tooltip: '刷新',
                  onPressed: _refreshViewData,
                  icon: const Icon(Icons.refresh_rounded),
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
                    recentCount == 0
                        ? '还没有导入资料，先试试拍照或从相册选择一张图片'
                        : '最近已保存 $recentCount 份资料，继续导入后会自动出现在下方记录中',
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
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

  Widget _buildQuickActionsSection() {
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
                onTap: _isImporting
                    ? null
                    : () => _handleImageImport(ImageInputSource.camera),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.camera_alt_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '拍照录入题目 / 讲义 / 课件',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '拍完后自动保存原始资料并进入详情页',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _isImporting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                            ),
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
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _QuickActionTile(
                      icon: Icons.image_rounded,
                      title: '导入图片',
                      subtitle: '从相册选择一张图片后立即入库',
                      color: const Color(0xFFE0F2FE),
                      onTap: _isImporting
                          ? null
                          : () => _handleImageImport(ImageInputSource.gallery),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _QuickActionTile(
                      icon: Icons.description_rounded,
                      title: '导入讲义/课件',
                      subtitle: 'PDF 与课件导入将在后续阶段接入',
                      color: const Color(0xFFFFF7ED),
                      onTap: () => _showComingSoon('讲义/课件导入'),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _QuickActionTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'AI 生成',
                      subtitle: '第七阶段先不接入 OCR 和 AI 生成',
                      color: const Color(0xFFF5F3FF),
                      onTap: () => _showComingSoon('AI 生成'),
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

  Widget _buildRecentRecordsSection(List<SourceDocumentRecord> recentDocuments) {
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
          if (recentDocuments.isEmpty)
            const _EmptyRecentRecords()
          else
            ...recentDocuments.map(
              (document) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RecentRecordCard(
                  document: document,
                  onTap: () => _openDocumentDetail(document),
                ),
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
              const columns = 2;
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

// ========== 页面局部组件 ==========
// 下面是首页各个区域用到的轻量展示组件，便于单文件内按模块维护。

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
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0B1324),
            ),
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
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Opacity(
            opacity: isEnabled ? 1 : 0.75,
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
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
  const _RecentRecordCard({required this.document, required this.onTap});

  final SourceDocumentRecord document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD1FAE5)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Image.file(
                    File(document.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFFE2E8F0),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            document.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: const Color(0xFF0B1324),
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            document.sourceTypeLabel,
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
                      document.createdAtLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _StatusTag(
                          label: document.ocrDone ? 'OCR 已完成' : '待 OCR',
                          done: document.ocrDone,
                        ),
                        const SizedBox(width: 8),
                        _StatusTag(
                          label: document.aiDone ? 'AI 已完成' : '待 AI',
                          done: document.aiDone,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

class _EmptyRecentRecords extends StatelessWidget {
  const _EmptyRecentRecords();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.collections_outlined,
            size: 34,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(height: 10),
          Text(
            '还没有导入资料',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xFF0B1324),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '点上面的拍照或导入图片，成功后这里会展示真实记录。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
          ),
        ],
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
                maxLines: 4,
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

class _HomeStatePanel extends StatelessWidget {
  const _HomeStatePanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF64748B)),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0B1324),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onPressed(),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== 首页视图数据 ==========
// 聚合首页当前用户与最近资料记录，减少页面层零散 Future 处理。

class _HomeTabViewData {
  const _HomeTabViewData({
    required this.currentUser,
    required this.recentDocuments,
  });

  final UserProfile currentUser;
  final List<SourceDocumentRecord> recentDocuments;
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
