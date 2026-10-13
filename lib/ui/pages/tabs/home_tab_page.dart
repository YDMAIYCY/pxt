import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../camera/document_input_contract.dart';
import '../../../common/app_assets.dart';
import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/document_batch_repository.dart';
import '../../../database/knowledge_graph_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/document_batch_record.dart';
import '../../../database/models/knowledge_library_record.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/models/user_profile.dart';
import '../../../database/source_document_repository.dart';
import '../../../pipeline/document_ingest_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/premium_app_chrome.dart';
import '../../widgets/create_knowledge_library_dialog.dart';
import '../document_batch_detail_page.dart';
import '../document_detail_page.dart';
import '../image_crop_selection_page.dart';
import '../qsclaw_agent_page.dart';
import '../home_page.dart';

class HomeTabPage extends StatefulWidget {
  const HomeTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.aiGenerationRepository,
    this.documentBatchRepository,
    this.knowledgeGraphRepository,
    this.knowledgeLibraryRepository,
    this.documentIngestService,
    this.detailPageBuilder,
    this.aiGenerationPageBuilder,
    this.aiChatPageBuilder,
    this.qsClawPageBuilder,
    this.refreshVersion = 0,
    this.refreshListenable,
    this.activeTabListenable,
    this.tabIndex,
    this.onOpenTab,
    this.onDataChanged,
    super.key,
  });

  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final DocumentBatchRepository? documentBatchRepository;
  final KnowledgeGraphRepository? knowledgeGraphRepository;
  final KnowledgeLibraryRepository? knowledgeLibraryRepository;
  final DocumentIngestService? documentIngestService;
  final Widget Function(int documentId)? detailPageBuilder;
  final Widget Function(int documentId)? aiGenerationPageBuilder;
  final Widget Function()? aiChatPageBuilder;
  final Widget Function()? qsClawPageBuilder;
  final int refreshVersion;
  final ValueListenable<int>? refreshListenable;
  final ValueListenable<int>? activeTabListenable;
  final int? tabIndex;
  final ValueChanged<int>? onOpenTab;
  final VoidCallback? onDataChanged;

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final DocumentBatchRepository _documentBatchRepository;
  late final KnowledgeGraphRepository _knowledgeGraphRepository;
  late final KnowledgeLibraryRepository _knowledgeLibraryRepository;
  late final DocumentIngestService _documentIngestService;
  late Future<_HomeData> _future;
  late int _handledRefreshVersion;
  bool _reloadScheduled = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _documentBatchRepository =
        widget.documentBatchRepository ?? DocumentBatchRepository();
    _knowledgeGraphRepository =
        widget.knowledgeGraphRepository ?? KnowledgeGraphRepository();
    _knowledgeLibraryRepository =
        widget.knowledgeLibraryRepository ?? KnowledgeLibraryRepository();
    _documentIngestService =
        widget.documentIngestService ?? DocumentIngestService();
    _handledRefreshVersion = widget.refreshVersion;
    widget.refreshListenable?.addListener(_handleExternalRefresh);
    widget.activeTabListenable?.addListener(_handleExternalRefresh);
    _future = _loadData();
  }

  @override
  void didUpdateWidget(covariant HomeTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_handleExternalRefresh);
      widget.refreshListenable?.addListener(_handleExternalRefresh);
    }
    if (oldWidget.activeTabListenable != widget.activeTabListenable) {
      oldWidget.activeTabListenable?.removeListener(_handleExternalRefresh);
      widget.activeTabListenable?.addListener(_handleExternalRefresh);
    }
    if (widget.refreshVersion != _handledRefreshVersion) {
      _handledRefreshVersion = widget.refreshVersion;
      _scheduleReload();
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_handleExternalRefresh);
    widget.activeTabListenable?.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  bool get _canHandleExternalRefresh {
    final tabIndex = widget.tabIndex;
    final activeTab = widget.activeTabListenable?.value;
    return tabIndex == null || activeTab == null || activeTab == tabIndex;
  }

  void _handleExternalRefresh() {
    if (!_canHandleExternalRefresh) return;
    _scheduleReload();
  }

  void _scheduleReload() {
    if (!mounted || _reloadScheduled) return;
    _reloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reloadScheduled = false;
      _reload();
    });
  }

  Future<_HomeData> _loadData() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) {
      throw StateError('\u767b\u5f55\u72b6\u6001\u5df2\u5931\u6548');
    }

    final recentDocuments = await _sourceDocumentRepository
        .fetchRecentSourceDocuments(
          userId: user.id,
          includeBatchPages: false,
          limit: 6,
        );
    final recentBatches = await _documentBatchRepository.fetchRecentBatches(
      userId: user.id,
      limit: 4,
    );
    final recentContents = await _aiGenerationRepository
        .fetchRecentGeneratedContents(userId: user.id, limit: 8);
    final stats = await _aiGenerationRepository.fetchStudyOverviewStats(
      user.id,
    );
    final nextActions = await _fetchNextActionsSafely(user.id);

    return _HomeData(
      user: user,
      recentBatches: recentBatches,
      recentDocuments: recentDocuments,
      recentContents: recentContents,
      stats: stats,
      nextActions: nextActions,
    );
  }

  Future<List<KnowledgeNextBestAction>> _fetchNextActionsSafely(
    int userId,
  ) async {
    try {
      return await _knowledgeGraphRepository.fetchNextBestActions(
        userId: userId,
        limit: 3,
      );
    } catch (_) {
      return const <KnowledgeNextBestAction>[];
    }
  }

  Future<void> _refresh() async {
    final future = _reload();
    await future;
  }

  Future<_HomeData> _reload() {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    return future;
  }

  Future<void> _afterDataChanged() async {
    final onDataChanged = widget.onDataChanged;
    if (onDataChanged != null) {
      onDataChanged();
      return;
    }
    await _refresh();
  }

  Future<void> _handleImageImport(ImageInputSource source) async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final user = await _authRepository.getCurrentUserProfile();
      if (user == null) {
        _showMessage('\u767b\u5f55\u72b6\u6001\u5df2\u5931\u6548');
        return;
      }
      final library = await _chooseLibraryForImport(user.id);
      if (!mounted || library == null) return;
      final document = await _documentIngestService.importFromInput(
        userId: user.id,
        libraryId: library.id,
        source: source,
      );
      if (!mounted || document == null) return;
      await _offerCropForImportedDocument(document);
      if (!mounted) return;
      if (document.importRecordId != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HomePage(
              initialTab: 1,
              initialRecordId: document.importRecordId,
              autoOcr: true,
            ),
          ),
        );
        if (mounted) await _afterDataChanged();
      } else {
        await _openDocument(document.id);
      }
    } catch (error) {
      if (mounted) _showMessage('\u5bfc\u5165\u5931\u8d25\uff1a$error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _offerCropForImportedDocument(
    SourceDocumentRecord document,
  ) async {
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImageCropSelectionPage(imagePath: document.imagePath),
      ),
    );
    if (!mounted || croppedPath == null || croppedPath.trim().isEmpty) {
      return;
    }

    await _sourceDocumentRepository.updateDocumentImagePath(
      userId: document.userId,
      documentId: document.id,
      imagePath: croppedPath,
    );
  }

  Future<void> _handleBatchImport(BatchDocumentInputSource source) async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final user = await _authRepository.getCurrentUserProfile();
      if (user == null) {
        _showMessage('\u767b\u5f55\u72b6\u6001\u5df2\u5931\u6548');
        return;
      }
      final library = await _chooseLibraryForImport(user.id);
      if (!mounted || library == null) return;
      final batch = await _documentIngestService.importBatchFromInput(
        userId: user.id,
        libraryId: library.id,
        source: source,
      );
      if (!mounted || batch == null) return;
      if (batch.importRecordId != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HomePage(
              initialTab: 1,
              initialRecordId: batch.importRecordId,
              autoOcr: true,
            ),
          ),
        );
        if (mounted) await _afterDataChanged();
      } else {
        await _openBatch(batch.id);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('\u6279\u91cf\u5bfc\u5165\u5931\u8d25\uff1a$error');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<KnowledgeLibraryRecord?> _chooseLibraryForImport(int userId) async {
    while (mounted) {
      final libraries = await _knowledgeLibraryRepository.fetchLibraries(
        userId,
      );
      if (!mounted) return null;

      final selectedId = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\u9009\u62e9\u4fdd\u5b58\u5230\u54ea\u4e2a\u77e5\u8bc6\u5e93',
                    style: AppTextStyles.h3(sheetContext),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...libraries.map(
                          (library) => ListTile(
                            leading: const Icon(
                              Icons.collections_bookmark_rounded,
                              color: AppColors.primary,
                            ),
                            title: Text(library.name),
                            subtitle: Text(
                              '${library.documentCount} \u4efd\u8d44\u6599',
                            ),
                            onTap: () =>
                                Navigator.of(sheetContext).pop(library.id),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(
                            Icons.add_rounded,
                            color: AppColors.primary,
                          ),
                          title: const Text('\u65b0\u5efa\u77e5\u8bc6\u5e93'),
                          onTap: () => Navigator.of(sheetContext).pop(-1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (selectedId == null) return null;
      if (selectedId == -1) {
        final created = await _promptCreateLibrary(userId);
        if (created != null) return created;
        continue;
      }
      return libraries.firstWhere((library) => library.id == selectedId);
    }
    return null;
  }

  Future<KnowledgeLibraryRecord?> _promptCreateLibrary(int userId) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CreateKnowledgeLibraryDialog(),
    );
    if (name == null || name.trim().isEmpty) return null;
    try {
      return await _knowledgeLibraryRepository.createLibrary(
        userId: userId,
        name: name,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('\u521b\u5efa\u77e5\u8bc6\u5e93\u5931\u8d25\uff1a$error');
      }
      return null;
    }
  }

  Future<void> _openDocument(int documentId) async {
    final page =
        widget.detailPageBuilder?.call(documentId) ??
        DocumentDetailPage(documentId: documentId);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openBatch(int batchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentBatchDetailPage(batchId: batchId),
      ),
    );
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openImportSourceSheet() async {
    final action = await showModalBottomSheet<_ImportAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('导入图片'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ImportAction.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.collections_rounded),
                title: const Text('多图导入'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ImportAction.multiImage),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: const Text('导入 PDF'),
                onTap: () => Navigator.of(sheetContext).pop(_ImportAction.pdf),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ImportAction.gallery:
        await _handleImageImport(ImageInputSource.gallery);
      case _ImportAction.multiImage:
        await _handleBatchImport(BatchDocumentInputSource.multiImage);
      case _ImportAction.pdf:
        await _handleBatchImport(BatchDocumentInputSource.pdf);
    }
  }

  Future<void> _openQsClaw() async {
    final page = widget.qsClawPageBuilder?.call() ?? const QsClawAgentPage();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _afterDataChanged();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openTab(int index) {
    final onOpenTab = widget.onOpenTab;
    if (onOpenTab == null) {
      _showMessage('当前页面暂不支持跳转');
      return;
    }
    onOpenTab(index);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _StatePanel(
            icon: Icons.error_outline_rounded,
            title: '\u9996\u9875\u52a0\u8f7d\u5931\u8d25',
            description: '\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002',
            onPressed: _refresh,
          );
        }

        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            cacheExtent: 5000,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 104),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WelcomeCard(
                        user: data.user,
                        stats: data.stats,
                        onOpenKnowledge: () => _openTab(1),
                        onOpenTasks: () => _openTab(3),
                      ),
                      const SizedBox(height: 12),
                      _AgentCommandStrip(onOpenQsClaw: _openQsClaw),
                      const SizedBox(height: 12),
                      _NextBestActionSection(
                        actions: data.nextActions,
                        onOpenTasks: () => _openTab(3),
                        onOpenKnowledge: () => _openTab(1),
                      ),
                      const SizedBox(height: 12),
                      _QuickActions(
                        isImporting: _isImporting,
                        onCamera: () =>
                            _handleImageImport(ImageInputSource.camera),
                        onImport: _openImportSourceSheet,
                      ),
                      const SizedBox(height: 14),
                      _RecentLearningGrid(
                        batches: data.recentBatches,
                        documents: data.recentDocuments,
                        onOpenBatch: _openBatch,
                        onOpenDocument: _openDocument,
                      ),
                      const SizedBox(height: 14),
                      _RecentResultsSection(
                        contents: data.recentContents,
                        onOpenDocument: _openDocument,
                      ),
                      const SizedBox(height: 14),
                      _StatsSection(stats: data.stats),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ========== Welcome Card ==========
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.user,
    required this.stats,
    required this.onOpenKnowledge,
    required this.onOpenTasks,
  });

  final UserProfile user;
  final StudyOverviewStats stats;
  final VoidCallback onOpenKnowledge;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final pendingWork = stats.pendingPracticeCount;
    return PremiumHeroPanel(
      asset: AppAssets.homeBackdropImage,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
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
                    Text(
                      '你好， ${user.primaryName}',
                      style: AppTextStyles.h1(context).copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.primaryLight.withValues(alpha: 0.62),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '今日概览',
                      style: AppTextStyles.caption(context).copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _PulseMetric(
                  label: '待办任务',
                  value: pendingWork,
                  color: AppColors.primary,
                  onTap: onOpenTasks,
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _PulseMetric(
                  label: '学习成果',
                  value: stats.generatedResultCount,
                  color: AppColors.secondaryBlue,
                  onTap: onOpenKnowledge,
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _PulseMetric(
                  label: '待刷练习',
                  value: stats.pendingPracticeCount,
                  color: AppColors.accentOrange,
                  onTap: onOpenTasks,
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _PulseMetric(
                  label: '待处理错题',
                  value: stats.wrongQuestionCount,
                  color: AppColors.error,
                  onTap: onOpenTasks,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppColors.borderLight,
    );
  }
}

class _AgentCommandStrip extends StatelessWidget {
  const _AgentCommandStrip({required this.onOpenQsClaw});

  final VoidCallback onOpenQsClaw;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenQsClaw,
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.cardSoftList,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9FBF8),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/qsclaw_robot_icon.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.smart_toy_rounded,
                              color: AppColors.primary,
                              size: 38,
                            ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'QSClaw',
                                  style: AppTextStyles.h2(context).copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '你的专属拍学通智能助手。',
                              maxLines: 4,
                              softWrap: true,
                              style: AppTextStyles.bodySmall(context).copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onOpenQsClaw,
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const Text('开始聊天'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseMetric extends StatelessWidget {
  const _PulseMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$value',
                style: AppTextStyles.h2(context).copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                softWrap: true,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(context).copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextBestActionSection extends StatelessWidget {
  const _NextBestActionSection({
    required this.actions,
    required this.onOpenTasks,
    required this.onOpenKnowledge,
  });

  final List<KnowledgeNextBestAction> actions;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenKnowledge;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return _Section(
        title: '下一步推荐',
        child: const _EmptyHint(text: '导入资料并生成知识图谱后，QSClaw 会根据薄弱知识点推荐下一步。'),
      );
    }

    final primary = actions.first;
    return _Section(
      title: '下一步推荐',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primary.actionLabel,
                        style: AppTextStyles.h3(
                          context,
                        ).copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${primary.concept.name} / ${primary.reason}',
                        maxLines: 4,
                        softWrap: true,
                        style: AppTextStyles.bodySmall(context).copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ...actions.map(
            (action) => _NextActionTile(
              action: action,
              onTap: action.concept.weaknessScore >= 70
                  ? onOpenTasks
                  : onOpenKnowledge,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextActionTile extends StatelessWidget {
  const _NextActionTile({required this.action, required this.onTap});

  final KnowledgeNextBestAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final concept = action.concept;
    return _ListTileShell(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.hub_rounded, color: AppColors.primary),
      ),
      title: concept.name,
      subtitle:
          '${action.documentTitle} | 掌握 ${concept.masteryScore} | 薄弱 ${concept.weaknessScore}',
      body: action.actionLabel,
    );
  }
}

// ========== Quick Actions ==========
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.isImporting,
    required this.onCamera,
    required this.onImport,
  });

  final bool isImporting;
  final VoidCallback onCamera;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '快速入口',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: width,
                child: _ActionTile(
                  iconAsset: AppAssets.iconCamera,
                  title: '拍照识别',
                  onTap: isImporting ? null : onCamera,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  iconAsset: AppAssets.iconAlbum,
                  title: '导入资料',
                  onTap: isImporting ? null : onImport,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _ImportAction { gallery, multiImage, pdf }

// ========== Recent Learning Grid ==========
class _RecentLearningGrid extends StatelessWidget {
  const _RecentLearningGrid({
    required this.batches,
    required this.documents,
    required this.onOpenBatch,
    required this.onOpenDocument,
  });

  final List<DocumentBatchRecord> batches;
  final List<SourceDocumentRecord> documents;
  final Future<void> Function(int batchId) onOpenBatch;
  final Future<void> Function(int documentId) onOpenDocument;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final batchCard = _RecentBatchesSection(
          batches: batches.take(1).toList(growable: false),
          onOpenBatch: onOpenBatch,
        );
        final documentCard = _RecentDocumentsSection(
          documents: documents.take(2).toList(growable: false),
          onOpenDocument: onOpenDocument,
        );
        if (compact) {
          return Column(
            children: [batchCard, const SizedBox(height: 14), documentCard],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: batchCard),
            const SizedBox(width: 14),
            Expanded(child: documentCard),
          ],
        );
      },
    );
  }
}

// ========== Recent Batches ==========
class _RecentBatchesSection extends StatelessWidget {
  const _RecentBatchesSection({
    required this.batches,
    required this.onOpenBatch,
  });
  final List<DocumentBatchRecord> batches;
  final Future<void> Function(int batchId) onOpenBatch;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '最近学习包',
      child: batches.isEmpty
          ? const _EmptyHint(text: '导入 PDF 或多图后会出现在这里。')
          : Column(
              children: batches
                  .map(
                    (batch) => _BatchTile(
                      batch: batch,
                      onTap: () => onOpenBatch(batch.id),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

// ========== Recent Documents ==========
class _RecentDocumentsSection extends StatelessWidget {
  const _RecentDocumentsSection({
    required this.documents,
    required this.onOpenDocument,
  });
  final List<SourceDocumentRecord> documents;
  final Future<void> Function(int documentId) onOpenDocument;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '最近处理资料',
      child: documents.isEmpty
          ? const _EmptyHint(text: '先拍照或导入图片。')
          : Column(
              children: documents
                  .map(
                    (document) => _DocumentTile(
                      document: document,
                      onTap: () => onOpenDocument(document.id),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

// ========== Recent Generated Results ==========
class _RecentResultsSection extends StatelessWidget {
  const _RecentResultsSection({
    required this.contents,
    required this.onOpenDocument,
  });
  final List<GeneratedContentRecord> contents;
  final Future<void> Function(int documentId) onOpenDocument;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '最近生成成果',
      child: contents.isEmpty
          ? const _EmptyHint(text: '生成知识卡片、提纲或练习题后会出现。')
          : Column(
              children: contents
                  .take(4)
                  .map(
                    (item) => _ResultTile(
                      item: item,
                      onTap: () => onOpenDocument(item.documentId),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

// ========== Study Stats ==========
class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.stats});
  final StudyOverviewStats stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem(
        '资料总数',
        stats.documentCount,
        const Color(0xFFF0FDFA),
        Icons.folder_rounded,
        AppColors.primary,
      ),
      _StatItem(
        'OCR \u8bc6\u522b',
        stats.ocrSuccessCount,
        const Color(0xFFEFF6FF),
        Icons.document_scanner_rounded,
        AppColors.secondaryBlue,
      ),
      _StatItem(
        '学习成果',
        stats.generatedResultCount,
        const Color(0xFFF5F3FF),
        Icons.school_rounded,
        AppColors.secondaryPurple,
      ),
      _StatItem(
        '待刷练习',
        stats.pendingPracticeCount,
        const Color(0xFFFFF7ED),
        Icons.edit_rounded,
        AppColors.accentOrange,
      ),
      _StatItem(
        '待处理错题',
        stats.wrongQuestionCount,
        const Color(0xFFFEF2F2),
        Icons.warning_rounded,
        AppColors.error,
      ),
      _StatItem(
        '已掌握',
        stats.masteredQuestionCount,
        const Color(0xFFF0FDF4),
        Icons.check_circle_rounded,
        AppColors.success,
      ),
    ];

    return _Section(
      title: '学习统计',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 50) / 6;
          final fallbackWidth = (constraints.maxWidth - 20) / 3;
          final itemWidth = width < 76 ? fallbackWidth : width;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items
                .map(
                  (item) => SizedBox(
                    width: itemWidth,
                    child: _StatCard(item: item),
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

// ========== Shared Components ==========
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumSectionHeader(title: title),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.iconAsset,
    required this.title,
    required this.onTap,
  });
  final String iconAsset;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: 52,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4ECEB)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF14B8A6).withValues(alpha: 0.025),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                iconAsset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  AppColors.primary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.document, required this.onTap});
  final SourceDocumentRecord document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ListTileShell(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Image.file(
            File(document.imagePath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: AppColors.surfaceAlt,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
      ),
      title: document.title,
      subtitle:
          '${document.createdAtLabel} | OCR ${document.ocrStatusLabel} | AI ${document.aiDone ? '已生成' : '待生成'}',
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.batch, required this.onTap});
  final DocumentBatchRecord batch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ListTileShell(
      onTap: onTap,
      leading: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.folder_copy_rounded,
          color: AppColors.primary,
          size: 34,
        ),
      ),
      title: batch.title,
      subtitle:
          '${batch.sourceTypeLabel} / ${batch.pageCount} 页\n${batch.createdAtLabel}',
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.item, required this.onTap});
  final GeneratedContentRecord item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ListTileShell(
      onTap: onTap,
      leading: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Icon(
          Icons.description_rounded,
          color: Colors.white,
          size: 17,
        ),
      ),
      title: item.title,
      subtitle: '${item.contentLabel} | ${item.documentTitle}',
      body: item.summary,
    );
  }
}

class _ListTileShell extends StatelessWidget {
  const _ListTileShell({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.body,
  });
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FCFB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 4,
                        softWrap: true,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 4,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      if (body?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          body!,
                          maxLines: 5,
                          softWrap: true,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.item});
  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: item.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${item.value}',
            style: AppTextStyles.h2(context).copyWith(
              color: item.foreground,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            item.label,
            maxLines: 2,
            softWrap: true,
            style: AppTextStyles.caption(context).copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Icon(item.icon, color: item.foreground, size: 22),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FCFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall(context),
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });
  final IconData icon;
  final String title;
  final String description;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => onPressed(),
              child: const Text('\u91cd\u8bd5'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.user,
    required this.recentBatches,
    required this.recentDocuments,
    required this.recentContents,
    required this.stats,
    required this.nextActions,
  });
  final UserProfile user;
  final List<DocumentBatchRecord> recentBatches;
  final List<SourceDocumentRecord> recentDocuments;
  final List<GeneratedContentRecord> recentContents;
  final StudyOverviewStats stats;
  final List<KnowledgeNextBestAction> nextActions;
}

class _StatItem {
  const _StatItem(
    this.label,
    this.value,
    this.color,
    this.icon,
    this.foreground,
  );
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final Color foreground;
}
