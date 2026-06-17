import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../camera/document_input_contract.dart';
import '../../../common/app_assets.dart';
import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/document_batch_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/document_batch_record.dart';
import '../../../database/models/knowledge_library_record.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/models/user_profile.dart';
import '../../../database/source_document_repository.dart';
import '../../../pipeline/document_ingest_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/create_knowledge_library_dialog.dart';
import '../ai_generation_page.dart';
import '../ai_chat_page.dart';
import '../document_batch_detail_page.dart';
import '../document_detail_page.dart';
import '../image_crop_selection_page.dart';
import '../qsclaw_agent_page.dart';
import '../../../game/games_hub_page.dart';
import '../practice_review_page.dart';

class HomeTabPage extends StatefulWidget {
  const HomeTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.aiGenerationRepository,
    this.documentBatchRepository,
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
    this.onDataChanged,
    super.key,
  });

  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final DocumentBatchRepository? documentBatchRepository;
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
  final VoidCallback? onDataChanged;

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final DocumentBatchRepository _documentBatchRepository;
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
    if (user == null) throw StateError('登录状态已失效');

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

    return _HomeData(
      user: user,
      recentBatches: recentBatches,
      recentDocuments: recentDocuments,
      recentContents: recentContents,
      stats: stats,
    );
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
        _showMessage('登录状态已失效');
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
      await _openDocument(document.id);
    } catch (error) {
      if (mounted) _showMessage('导入失败：$error');
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
        _showMessage('登录状态已失效');
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
      await _openBatch(batch.id);
    } catch (error) {
      if (mounted) _showMessage('批量导入失败：$error');
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
                  Text('选择保存到哪个知识库', style: AppTextStyles.h3(sheetContext)),
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
                            subtitle: Text('${library.documentCount} 份资料'),
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
                          title: const Text('新建知识库'),
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
      if (mounted) _showMessage('创建知识库失败：$error');
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

  Future<void> _openAiGeneration() async {
    final user = await _authRepository.getCurrentUserProfile();
    if (!mounted) return;
    if (user == null) {
      _showMessage('鐧诲綍鐘舵€佸凡澶辨晥');
      return;
    }
    final documents = await _sourceDocumentRepository
        .fetchRecentSourceDocuments(
          userId: user.id,
          includeBatchPages: true,
          limit: 100,
        );
    if (!mounted) return;
    final target = documents.cast<SourceDocumentRecord?>().firstWhere(
      (item) => item?.ocrDone == true,
      orElse: () => null,
    );
    if (target == null) {
      _showMessage('请先完成任意资料的 OCR，再生成 AI 结果');
      return;
    }
    final page =
        widget.aiGenerationPageBuilder?.call(target.id) ??
        AiGenerationPage(documentId: target.id);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openAiChat() async {
    final page = widget.aiChatPageBuilder?.call() ?? const AiChatPage();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openQsClaw() async {
    final page = widget.qsClawPageBuilder?.call() ?? const QsClawAgentPage();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openPractice() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PracticeReviewPage()));
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openGames() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GamesHubPage()));
    if (mounted) await _refresh();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            title: '首页加载失败',
            description: '请稍后重试。',
            onPressed: _refresh,
          );
        }

        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WelcomeCard(user: data.user, stats: data.stats),
                      const SizedBox(height: 14),
                      _QuickActions(
                        isImporting: _isImporting,
                        onCamera: () =>
                            _handleImageImport(ImageInputSource.camera),
                        onGallery: () =>
                            _handleImageImport(ImageInputSource.gallery),
                        onMultiImage: () => _handleBatchImport(
                          BatchDocumentInputSource.multiImage,
                        ),
                        onPdf: () =>
                            _handleBatchImport(BatchDocumentInputSource.pdf),
                        onAi: _openAiGeneration,
                        onAiChat: _openAiChat,
                        onQsClaw: _openQsClaw,
                        onPractice: _openPractice,
                        onGames: _openGames,
                      ),
                      const SizedBox(height: 14),
                      _RecentBatchesSection(
                        batches: data.recentBatches,
                        onOpenBatch: _openBatch,
                      ),
                      const SizedBox(height: 14),
                      _RecentDocumentsSection(
                        documents: data.recentDocuments,
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

// ========== 欢迎卡片 ==========
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.user, required this.stats});
  final UserProfile user;
  final StudyOverviewStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCCFBF1), Color(0xFFF0FDFA)],
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('你好，${user.primaryName}', style: AppTextStyles.h1(context)),
          const SizedBox(height: 6),
          Text(
            '已保存 ${stats.documentCount} 份资料，生成 ${stats.generatedResultCount} 条学习成果。',
            style: AppTextStyles.bodySmall(context).copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ========== 快速入口 ==========
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.isImporting,
    required this.onCamera,
    required this.onGallery,
    required this.onMultiImage,
    required this.onPdf,
    required this.onAi,
    required this.onAiChat,
    required this.onQsClaw,
    required this.onPractice,
    required this.onGames,
  });

  final bool isImporting;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onMultiImage;
  final VoidCallback onPdf;
  final VoidCallback onAi;
  final VoidCallback onAiChat;
  final VoidCallback onQsClaw;
  final VoidCallback onPractice;
  final VoidCallback onGames;

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
                  title: '拍照资料',
                  onTap: isImporting ? null : onCamera,
                  isPrimary: true,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  iconAsset: AppAssets.iconAlbum,
                  title: '导入图片',
                  onTap: isImporting ? null : onGallery,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  iconAsset: AppAssets.iconPdfMulti,
                  title: '多图导入',
                  onTap: isImporting ? null : onMultiImage,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  iconAsset: AppAssets.iconPdfMulti,
                  title: '导入 PDF',
                  onTap: isImporting ? null : onPdf,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  iconAsset: AppAssets.iconAi,
                  title: '生成 AI 结果',
                  onTap: onAi,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  icon: Icons.smart_toy_rounded,
                  title: 'AI Chat',
                  onTap: onAiChat,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  icon: Icons.psychology_rounded,
                  title: 'QSClaw',
                  onTap: onQsClaw,
                  isPrimary: true,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  iconAsset: AppAssets.practiceQuestion,
                  title: '刷复习题',
                  onTap: onPractice,
                ),
              ),
              SizedBox(
                width: width,
                child: _ActionTile(
                  icon: Icons.games_rounded,
                  title: '益智游戏',
                  onTap: onGames,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ========== 最近学习包 ==========
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
          ? const _EmptyHint(text: '多图或 PDF 导入后，会在这里形成学习包。')
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

// ========== 最近处理资料 ==========
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
          ? const _EmptyHint(text: '还没有资料，先拍照或导入图片。')
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

// ========== 最近生成成果 ==========
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
          ? const _EmptyHint(text: '生成知识卡片、提纲、导图或复习题后会出现在这里。')
          : Column(
              children: contents
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

// ========== 学习统计 ==========
class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.stats});
  final StudyOverviewStats stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem('资料总数', stats.documentCount, const Color(0xFFF0FDFA)),
      _StatItem('OCR 完成', stats.ocrSuccessCount, const Color(0xFFEFF6FF)),
      _StatItem('学习成果', stats.generatedResultCount, const Color(0xFFF5F3FF)),
      _StatItem('待刷题', stats.pendingPracticeCount, const Color(0xFFFFF7ED)),
      _StatItem('待处理错题', stats.wrongQuestionCount, const Color(0xFFFEF2F2)),
      _StatItem('已掌握', stats.masteredQuestionCount, const Color(0xFFF0FDF4)),
    ];

    return _Section(
      title: '学习统计',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items
                .map(
                  (item) => SizedBox(
                    width: width,
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

// ========== 通用组件 ==========
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h3(context)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    this.icon,
    this.iconAsset,
    required this.title,
    required this.onTap,
    this.isPrimary = false,
  });
  final IconData? icon;
  final String? iconAsset;
  final String title;
  final VoidCallback? onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.primary : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.cardSmall),
            border: isPrimary ? null : Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              if (iconAsset != null)
                SvgPicture.asset(
                  iconAsset!,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    isPrimary ? Colors.white : AppColors.primary,
                    BlendMode.srcIn,
                  ),
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: 22,
                  color: isPrimary ? Colors.white : AppColors.primary,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isPrimary ? Colors.white : AppColors.textPrimary,
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
          width: 52,
          height: 52,
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
          '${document.createdAtLabel} / OCR ${document.ocrStatusLabel} / AI ${document.aiDone ? '已生成' : '待生成'}',
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
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.folder_copy_rounded, color: AppColors.primary),
      ),
      title: batch.title,
      subtitle:
          '${batch.sourceTypeLabel} / ${batch.pageCount} 页 / ${batch.createdAtLabel}',
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
      leading: const Icon(Icons.auto_stories_rounded, color: AppColors.primary),
      title: item.title,
      subtitle: '${item.documentTitle} / ${item.contentLabel}',
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
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (body?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          body!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.color,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.value}',
            style: AppTextStyles.h2(
              context,
            ).copyWith(color: AppColors.primaryDark),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: AppTextStyles.caption(context).copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
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
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.input),
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
            FilledButton(onPressed: () => onPressed(), child: const Text('重试')),
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
  });
  final UserProfile user;
  final List<DocumentBatchRecord> recentBatches;
  final List<SourceDocumentRecord> recentDocuments;
  final List<GeneratedContentRecord> recentContents;
  final StudyOverviewStats stats;
}

class _StatItem {
  const _StatItem(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}
