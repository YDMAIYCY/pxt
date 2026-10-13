import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../camera/document_input_contract.dart';
import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/document_batch_repository.dart';
import '../../../database/knowledge_graph_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/document_batch_record.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/source_document_repository.dart';
import '../../../pipeline/document_ingest_service.dart';
import '../../theme/app_theme.dart';
import '../document_batch_detail_page.dart';
import '../document_detail_page.dart';
import '../image_crop_selection_page.dart';
import '../ai_interview_page.dart';
import '../learning_hub_pages.dart';
import '../learning_workspace_page.dart';
import '../practice_review_page.dart';

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
    final stats = await _aiGenerationRepository.fetchStudyOverviewStats(
      user.id,
    );
    final nextActions = await _fetchNextActionsSafely(user.id);

    return _HomeData(
      recentBatches: recentBatches,
      recentDocuments: recentDocuments,
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
      final library = await _knowledgeLibraryRepository.ensureDefaultLibrary(
        user.id,
      );
      if (!mounted) return;
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
      final library = await _knowledgeLibraryRepository.ensureDefaultLibrary(
        user.id,
      );
      if (!mounted) return;
      final batch = await _documentIngestService.importBatchFromInput(
        userId: user.id,
        libraryId: library.id,
        source: source,
      );
      if (!mounted || batch == null) return;
      await _openBatch(batch.id);
    } catch (error) {
      if (mounted) {
        _showMessage('\u6279\u91cf\u5bfc\u5165\u5931\u8d25\uff1a$error');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
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
  Widget build(BuildContext context) => FutureBuilder<_HomeData>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('首页加载失败：${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 108),
          children: [
            Text('拍学通', style: AppTextStyles.h1(context)),
            const SizedBox(height: 6),
            Text('今天想学习什么？', style: AppTextStyles.body(context)),
            const SizedBox(height: 18),
            Card(
              color: AppColors.primarySoft,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('拍一下，开始学习', style: AppTextStyles.h2(context)),
                    const SizedBox(height: 8),
                    const Text('拍照、截屏、上传资料，让知识变得容易掌握'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: _isImporting
                              ? null
                              : () =>
                                    _handleImageImport(ImageInputSource.camera),
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text('拍照'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: _isImporting
                              ? null
                              : () => _handleImageImport(
                                  ImageInputSource.gallery,
                                ),
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('相册'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: _isImporting
                              ? null
                              : _openImportSourceSheet,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('文件'),
                        ),
                      ],
                    ),
                    if (_isImporting) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('继续学习', style: AppTextStyles.h3(context)),
            if (data.recentDocuments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('拍下你想学的，建立第一个知识包。'),
              )
            else
              Card(
                child: ListTile(
                  title: Text(data.recentDocuments.first.title),
                  subtitle: Text(
                    data.recentDocuments.first.lastConceptName == null
                        ? (data.recentDocuments.first.aiDone
                              ? '继续查看学习资源与知识点'
                              : '继续解析资料，整理学习重点')
                        : '上次学到：${data.recentDocuments.first.lastConceptName}',
                  ),
                  trailing: const Icon(Icons.play_circle_outline_rounded),
                  onTap: () => _openDocument(data.recentDocuments.first.id),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('今日学习建议', style: AppTextStyles.h3(context)),
                ),
                TextButton(
                  onPressed: () => _openTab(2),
                  child: const Text('查看全部'),
                ),
              ],
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('待复习知识'),
                subtitle: Text(
                  '按遗忘风险排序 · ${data.stats.pendingPracticeCount} 道待练习',
                ),
                onTap: () => openLearningPage(
                  context,
                  const PracticeReviewPage(),
                  onChanged: widget.onDataChanged,
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.flip_rounded),
                title: const Text('记忆闪卡复习'),
                subtitle: const Text('复习到期卡片，按记忆难度安排下次复习'),
                onTap: () => openLearningPage(
                  context,
                  const DueFlashcardsPage(),
                  onChanged: widget.onDataChanged,
                ),
              ),
            ),
            ...data.nextActions.map(
              (a) => Card(
                child: ListTile(
                  title: Text(a.concept.name),
                  subtitle: Text(a.reason),
                  onTap: () => openLearningPage(
                    context,
                    LearningWorkspacePage(
                      documentId: a.concept.documentId!,
                      conceptId: a.concept.id,
                    ),
                    onChanged: widget.onDataChanged,
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.record_voice_over_rounded),
                title: const Text('AI 快速面试'),
                subtitle: const Text('检验真正理解程度'),
                onTap: () => openLearningPage(
                  context,
                  const AiInterviewPage(),
                  onChanged: widget.onDataChanged,
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_note_rounded),
                title: const Text('到期任务'),
                subtitle: const Text('查看复习安排与待处理资料'),
                onTap: () => openLearningPage(
                  context,
                  const LearningPlansPage(),
                  onChanged: widget.onDataChanged,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('最近知识包', style: AppTextStyles.h3(context)),
            ...data.recentDocuments.map(
              (d) => ListTile(
                title: Text(d.title),
                subtitle: Text(d.ocrStatusLabel),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openDocument(d.id),
              ),
            ),
            ...data.recentBatches.map(
              (b) => ListTile(
                title: Text(b.title),
                subtitle: const Text('批量资料'),
                onTap: () => _openBatch(b.id),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _openTab(3),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('AI 学伴'),
            ),
          ],
        ),
      );
    },
  );
}

enum _ImportAction { gallery, multiImage, pdf }

class _HomeData {
  const _HomeData({
    required this.recentBatches,
    required this.recentDocuments,
    required this.stats,
    required this.nextActions,
  });
  final List<DocumentBatchRecord> recentBatches;
  final List<SourceDocumentRecord> recentDocuments;
  final StudyOverviewStats stats;
  final List<KnowledgeNextBestAction> nextActions;
}
