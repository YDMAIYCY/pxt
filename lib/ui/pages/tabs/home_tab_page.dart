import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../camera/document_input_contract.dart';
import '../../../common/app_assets.dart';
import '../../../database/app_database.dart';
import '../../../database/auth_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/models/knowledge_library_record.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/models/user_profile.dart';
import '../../../database/source_document_repository.dart';
import '../../../learning/learning_events.dart';
import '../../../learning/learning_task_repository.dart';
import '../../../pipeline/document_ingest_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/create_knowledge_library_dialog.dart';
import '../../widgets/knowledge_book_cover.dart';
import '../../widgets/premium_app_chrome.dart';
import '../document_detail_page.dart';
import '../home_page.dart';
import '../image_crop_selection_page.dart';
import '../interview/interview_prepare_page.dart';
import '../learning_concept_page.dart';
import '../library_practice_page.dart';
import '../qsclaw_agent_page.dart';

/// 首页 = 学习工作台：先回答“现在最该学什么”，再回答“为什么”和“从哪开始”。
class HomeTabPage extends StatefulWidget {
  const HomeTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.knowledgeLibraryRepository,
    this.learningTaskRepository,
    this.database,
    this.documentIngestService,
    this.detailPageBuilder,
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
  final KnowledgeLibraryRepository? knowledgeLibraryRepository;
  final LearningTaskRepository? learningTaskRepository;
  final AppDatabase? database;
  final DocumentIngestService? documentIngestService;
  final Widget Function(int documentId)? detailPageBuilder;
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
  late final KnowledgeLibraryRepository _knowledgeLibraryRepository;
  late final LearningTaskRepository _learningTaskRepository;
  late final DocumentIngestService _documentIngestService;
  late Future<_HomeData> _future;
  late int _handledRefreshVersion;
  int? _userId;
  bool _reloadScheduled = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository(database: widget.database);
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository(database: widget.database);
    _knowledgeLibraryRepository =
        widget.knowledgeLibraryRepository ?? KnowledgeLibraryRepository(database: widget.database);
    _learningTaskRepository =
        widget.learningTaskRepository ?? LearningTaskRepository(database: widget.database);
    _documentIngestService =
        widget.documentIngestService ?? DocumentIngestService();
    LearningEvents.changed.addListener(_handleExternalRefresh);
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
    LearningEvents.changed.removeListener(_handleExternalRefresh);
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
    // Learning events arrive outside a build, so the frame must be requested
    // explicitly or the reload would wait for an unrelated repaint.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<_HomeData> _loadData() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) {
      throw StateError('登录状态已失效');
    }
    _userId = user.id;
    final dashboard = await _learningTaskRepository.dashboard(user.id);
    final libraries = await _knowledgeLibraryRepository.fetchStudySummaries(
      userId: user.id,
    );
    final backlog = await _learningTaskRepository.practiceBacklog(
      user.id,
      limit: 3,
    );

    return _HomeData(
      user: user,
      dashboard: dashboard,
      libraries: libraries,
      todayTaskCount: _countTodayTasks(dashboard.tasks),
      recommendations: [
        ...dashboard.recommendations
            .take(4)
            .map(_HomeRecommendation.fromConcept),
        ...backlog.map(_HomeRecommendation.fromBacklog),
      ],
    );
  }

  static int _countTodayTasks(List<LearningTask> tasks) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return tasks
        .where(
          (task) =>
              task.active &&
              (task.dueAt == null || task.dueAt!.toLocal().isBefore(tomorrow)),
        )
        .length;
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
        await _openDocument(batch.id);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('批量导入失败：$error');
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
      if (mounted) {
        _showMessage('创建知识库失败：$error');
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
                title: const Text('相册导入'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ImportAction.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.description_rounded),
                title: const Text('文档导入'),
                subtitle: const Text('PDF、Word、PPT'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ImportAction.document),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ImportAction.gallery:
        await _handleBatchImport(BatchDocumentInputSource.multiImage);
      case _ImportAction.document:
        await _handleBatchImport(BatchDocumentInputSource.document);
    }
  }

  Future<void> _openQsClaw() async {
    final page = widget.qsClawPageBuilder?.call() ?? const QsClawAgentPage();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openInterview() async {
    final userId = _userId;
    if (userId == null) {
      _showMessage('登录状态已失效');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InterviewPreparePage(
          userId: userId,
          database: widget.database,
        ),
      ),
    );
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openLearningTask(LearningTask task) async {
    final Widget page;
    if (task.questionId != null) {
      page = LibraryPracticePage(
        initialQuestionId: task.questionId,
        documentId: task.documentId,
        database: widget.database,
      );
    } else if (task.conceptId != null) {
      page = LearningConceptPage(
        conceptId: task.conceptId!,
        database: widget.database,
        learningTaskRepository: _learningTaskRepository,
      );
    } else if (task.documentId != null) {
      await _openDocument(task.documentId!);
      return;
    } else {
      _openTab(3);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await _reload();
  }

  Future<void> _openRecommendation(_HomeRecommendation item) async {
    final Widget page;
    if (item.conceptId != null) {
      page = LearningConceptPage(
        conceptId: item.conceptId!,
        database: widget.database,
        learningTaskRepository: _learningTaskRepository,
      );
    } else if (item.questionIds.isNotEmpty) {
      page = LibraryPracticePage(
        questionIds: item.questionIds,
        initialQuestionId: item.questionIds.first,
        documentId: item.documentId,
        database: widget.database,
      );
    } else {
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await _reload();
  }

  Future<void> _openPracticeQuestions(int userId, String filter) async {
    final db = await (widget.database ?? AppDatabase.instance).database;
    final now = DateTime.now();
    final today = DateTime(
      now.year,
      now.month,
      now.day,
    ).toUtc().toIso8601String();
    final clause = switch (filter) {
      'wrong' =>
        "q.review_status='wrong' OR (q.wrong_count>0 AND q.review_status!='mastered')",
      'overdue' => 'q.next_review_at < ?',
      _ => "q.review_status='pending'",
    };
    final rows = await db.rawQuery(
      '''SELECT q.id FROM practice_questions q
      JOIN source_documents d ON d.id=q.document_id
      WHERE d.user_id=? AND ($clause) ORDER BY q.next_review_at, q.id''',
      [userId, if (filter == 'overdue') today],
    );
    final ids = rows.map((r) => r['id'] as int).toList();
    if (!mounted) return;
    if (ids.isEmpty) {
      _showMessage('当前没有对应的练习');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LibraryPracticePage(
          questionIds: ids,
          initialQuestionId: ids.first,
          database: widget.database,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _openSearch() async {
    final userId = _userId;
    if (userId == null) {
      _showMessage('登录状态已失效');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _StudySearchSheet(
        repository: _knowledgeLibraryRepository,
        userId: userId,
        onOpen: (hit) {
          Navigator.of(sheetContext).pop();
          _openSearchHit(hit);
        },
      ),
    );
  }

  Future<void> _openSearchHit(StudySearchHit hit) async {
    final conceptId = hit.conceptId;
    final questionId = hit.questionId;
    final documentId = hit.documentId;
    if (conceptId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LearningConceptPage(
            conceptId: conceptId,
            database: widget.database,
            learningTaskRepository: _learningTaskRepository,
          ),
        ),
      );
    } else if (questionId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LibraryPracticePage(
            questionIds: [questionId],
            initialQuestionId: questionId,
            documentId: documentId,
            database: widget.database,
          ),
        ),
      );
    } else if (documentId != null) {
      await _openDocument(documentId);
      return;
    } else {
      return;
    }
    if (mounted) await _reload();
  }

  Future<void> _openNotifications(_HomeData data) async {
    final userId = data.user.id;
    final notices = <_Notice>[
      if (data.dashboard.wrongQuestions > 0)
        _Notice(
          icon: Icons.error_outline_rounded,
          color: AppColors.error,
          title: '待处理错题 ${data.dashboard.wrongQuestions} 道',
          detail: '错题不订正会反复出现，建议今天清掉一批。',
          onTap: () => _openPracticeQuestions(userId, 'wrong'),
        ),
      if (data.dashboard.overduePractice > 0)
        _Notice(
          icon: Icons.event_busy_rounded,
          color: AppColors.accentOrange,
          title: '复习到期 ${data.dashboard.overduePractice} 个',
          detail: '按记忆曲线，这些内容今天复习效果最好。',
          onTap: () => _openPracticeQuestions(userId, 'overdue'),
        ),
      if (data.todayTaskCount > 0)
        _Notice(
          icon: Icons.checklist_rounded,
          color: AppColors.primary,
          title: '今日任务 ${data.todayTaskCount} 项',
          detail: '任务中心可以开始专注、调整顺序或推迟。',
          onTap: () => _openTab(3),
        ),
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('学习提醒', style: AppTextStyles.h2(sheetContext)),
              const SizedBox(height: 12),
              if (notices.isEmpty)
                Text(
                  '暂时没有待处理事项。保持当前节奏就好。',
                  style: AppTextStyles.bodySmall(sheetContext),
                )
              else
                ...notices.map(
                  (notice) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(notice.icon, color: notice.color),
                    title: Text(
                      notice.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(notice.detail),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      notice.onTap();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
            cacheExtent: 5000,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 104),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HomeHeader(
                        user: data.user,
                        onSearch: _openSearch,
                        onNotifications: () => _openNotifications(data),
                        onOpenAgent: _openQsClaw,
                      ),
                      const SizedBox(height: 16),
                      _CurrentTaskCard(
                        task: data.dashboard.tasks.firstOrNull,
                        onContinue: _openLearningTask,
                        onOpenTasks: () => _openTab(3),
                      ),
                      const SizedBox(height: 12),
                      _StudyOverviewCard(
                        todayTaskCount: data.todayTaskCount,
                        wrongQuestions: data.dashboard.wrongQuestions,
                        overduePractice: data.dashboard.overduePractice,
                        masteryPercent: data.masteryPercent,
                        onOpenTasks: () => _openTab(3),
                        onOpenWrong: () =>
                            _openPracticeQuestions(data.user.id, 'wrong'),
                        onOpenOverdue: () =>
                            _openPracticeQuestions(data.user.id, 'overdue'),
                      ),
                      const SizedBox(height: 12),
                      _QuickActionsCard(
                        isImporting: _isImporting,
                        onCamera: () =>
                            _handleImageImport(ImageInputSource.camera),
                        onImport: _openImportSourceSheet,
                        onInterview: _openInterview,
                        onOpenAgent: _openQsClaw,
                      ),
                      const SizedBox(height: 12),
                      _RecommendationCard(
                        recommendations: data.recommendations,
                        onOpen: _openRecommendation,
                        onOpenTasks: () => _openTab(3),
                      ),
                      const SizedBox(height: 12),
                      _MyLibrariesCard(
                        libraries: data.recentLibraries,
                        onOpenLibrary: () => _openTab(1),
                      ),
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

// ========== 顶部欢迎区 ==========
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.user,
    required this.onSearch,
    required this.onNotifications,
    required this.onOpenAgent,
  });

  final UserProfile user;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final VoidCallback onOpenAgent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${_greeting(DateTime.now())}，${user.primaryName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _HeaderIconButton(
              icon: Icons.search_rounded,
              tooltip: '搜索学习内容',
              onTap: onSearch,
            ),
            const SizedBox(width: 4),
            _HeaderIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: '学习提醒',
              onTap: onNotifications,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '今天也要加油学习，先把最要紧的一件事做完。',
          maxLines: 2,
          style: AppTextStyles.bodySmall(context).copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        _EclawPill(onTap: onOpenAgent),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.borderLight),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 21, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _EclawPill extends StatelessWidget {
  const _EclawPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            border: Border.all(color: AppColors.primaryLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/eclaw_robot_avatar.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.smart_toy_rounded,
                    size: 17,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'EClaw',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '随时陪你学习',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(context).copyWith(fontSize: 11),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========== 当前任务 ==========
class _CurrentTaskCard extends StatelessWidget {
  const _CurrentTaskCard({
    required this.task,
    required this.onContinue,
    required this.onOpenTasks,
  });

  final LearningTask? task;
  final ValueChanged<LearningTask> onContinue;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final current = task;
    return _SectionCard(
      title: '当前任务',
      actionLabel: '查看全部',
      onAction: onOpenTasks,
      child: current == null
          ? _EmptyHint(
              icon: Icons.playlist_add_check_rounded,
              text: '今天还没有安排任务，先去任务中心定一个学习目标。',
              actionLabel: '新建学习任务',
              onAction: onOpenTasks,
            )
          : _CurrentTaskBody(task: current, onContinue: onContinue),
    );
  }
}

class _CurrentTaskBody extends StatelessWidget {
  const _CurrentTaskBody({required this.task, required this.onContinue});

  final LearningTask task;
  final ValueChanged<LearningTask> onContinue;

  @override
  Widget build(BuildContext context) {
    final source = [task.libraryName, task.documentTitle]
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');
    final minutes = task.focusedSeconds ~/ 60;
    final target = task.estimatedPomodoros * 25;
    final progress = target <= 0 ? 0.0 : (minutes / target).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                  letterSpacing: -0.2,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => onContinue(task),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('继续学习'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Tag(label: task.kindLabel, tone: _TagTone.primary),
            if (source.isNotEmpty) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.menu_book_rounded,
                size: 14,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(context).copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceMuted,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                minutes == 0
                    ? '尚未开始专注 · 预计 ${task.estimatedPomodoros} 个番茄'
                    : '已专注 $minutes 分钟 · 预计 ${task.estimatedPomodoros} 个番茄',
                style: AppTextStyles.caption(context).copyWith(fontSize: 12),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: AppTextStyles.caption(context).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ========== 学习概览 ==========
class _StudyOverviewCard extends StatelessWidget {
  const _StudyOverviewCard({
    required this.todayTaskCount,
    required this.wrongQuestions,
    required this.overduePractice,
    required this.masteryPercent,
    required this.onOpenTasks,
    required this.onOpenWrong,
    required this.onOpenOverdue,
  });

  final int todayTaskCount, wrongQuestions, overduePractice;
  final int? masteryPercent;
  final VoidCallback onOpenTasks, onOpenWrong, onOpenOverdue;

  @override
  Widget build(BuildContext context) {
    final metrics = <Widget>[
      _OverviewMetric(
        label: '今日任务',
        value: '$todayTaskCount',
        onTap: onOpenTasks,
      ),
      _OverviewMetric(
        label: '待处理错题',
        value: '$wrongQuestions',
        emphasis: wrongQuestions > 0 ? AppColors.error : null,
        onTap: onOpenWrong,
      ),
      _OverviewMetric(
        label: '复习到期',
        value: '$overduePractice',
        emphasis: overduePractice > 0 ? AppColors.accentOrange : null,
        onTap: onOpenOverdue,
      ),
      _OverviewMetric(
        label: '整体掌握度',
        value: masteryPercent == null ? '—' : '$masteryPercent%',
      ),
    ];

    return _SectionCard(
      title: '学习概览',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            if (index > 0)
              Container(
                width: 1,
                height: 42,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: AppColors.borderLight,
              ),
            Expanded(child: metrics[index]),
          ],
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    this.emphasis,
    this.onTap,
  });

  final String label, value;
  final Color? emphasis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
              color: emphasis ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption(context).copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}

// ========== 快捷操作 ==========
class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.isImporting,
    required this.onCamera,
    required this.onImport,
    required this.onInterview,
    required this.onOpenAgent,
  });

  final bool isImporting;
  final VoidCallback onCamera, onImport, onInterview, onOpenAgent;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '快捷操作',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _QuickActionTile(
              iconAsset: AppAssets.iconCamera,
              label: '拍照识别',
              onTap: isImporting ? null : onCamera,
            ),
          ),
          Expanded(
            child: _QuickActionTile(
              iconAsset: AppAssets.iconAlbum,
              label: '导入资料',
              onTap: isImporting ? null : onImport,
            ),
          ),
          Expanded(
            child: _QuickActionTile(
              iconAsset: AppAssets.iconAi,
              label: 'AI 面试',
              onTap: onInterview,
            ),
          ),
          Expanded(
            child: _QuickActionTile(
              avatarAsset: 'assets/images/eclaw_robot_avatar.png',
              label: '问 EClaw',
              onTap: onOpenAgent,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.label,
    required this.onTap,
    this.iconAsset,
    this.avatarAsset,
  });

  final String label;
  final VoidCallback? onTap;
  final String? iconAsset, avatarAsset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: avatarAsset != null
                    ? Padding(
                        padding: const EdgeInsets.all(4),
                        child: Image.asset(
                          avatarAsset!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.smart_toy_rounded,
                            size: 21,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : SvgPicture.asset(
                        iconAsset!,
                        width: 22,
                        height: 22,
                        colorFilter: const ColorFilter.mode(
                          AppColors.primary,
                          BlendMode.srcIn,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========== 为你推荐 ==========
class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({
    required this.recommendations,
    required this.onOpen,
    required this.onOpenTasks,
  });

  final List<_HomeRecommendation> recommendations;
  final ValueChanged<_HomeRecommendation> onOpen;
  final VoidCallback onOpenTasks;

  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  bool _weakOnly = false;

  @override
  Widget build(BuildContext context) {
    final items = _weakOnly
        ? widget.recommendations.where((item) => item.weak).take(3).toList()
        : widget.recommendations.take(3).toList();

    return _SectionCard(
      title: '为你推荐',
      subtitle: _weakOnly ? '掌握度偏低的内容，优先补上' : '按掌握情况和复习到期时间排序',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegmentedTabs(
            selectedIndex: _weakOnly ? 1 : 0,
            labels: const ['今日推荐', '薄弱提升'],
            onSelect: (index) => setState(() => _weakOnly = index == 1),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            _EmptyHint(
              icon: Icons.lightbulb_outline_rounded,
              text: _weakOnly
                  ? '目前没有明显薄弱的内容，保持现在的节奏就好。'
                  : '完成练习或设置复习计划后，这里会给出下一步建议。',
              actionLabel: '查看任务中心',
              onAction: widget.onOpenTasks,
            )
          else
            ...items.map(
              (item) => _RecommendationTile(
                item: item,
                onTap: () => widget.onOpen(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({required this.item, required this.onTap});

  final _HomeRecommendation item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPractice = item.kind == _RecommendationKind.practice;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceAlt.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final leading = Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isPractice
                        ? const Color(0xFFFEF3E7)
                        : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPractice
                        ? Icons.edit_note_rounded
                        : Icons.psychology_alt_rounded,
                    size: 20,
                    color: isPractice
                        ? AppColors.accentOrange
                        : AppColors.primary,
                  ),
                );
                final body = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Tag(
                          label: item.badge,
                          tone: isPractice
                              ? _TagTone.warning
                              : _TagTone.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.reason,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(context).copyWith(
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
                final action = OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    side: const BorderSide(color: AppColors.primaryLight),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(isPractice ? '开始练习' : '开始复习'),
                );

                // 窄屏放不下“文字 + 按钮”并排，按钮换行到右下角。
                if (constraints.maxWidth < 290) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          leading,
                          const SizedBox(width: 10),
                          Expanded(child: body),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: action,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    const SizedBox(width: 10),
                    Expanded(child: body),
                    const SizedBox(width: 8),
                    action,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: Material(
                color: index == selectedIndex
                    ? AppColors.surface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.chip),
                child: InkWell(
                  onTap: () => onSelect(index),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: index == selectedIndex
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: index == selectedIndex
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ========== 我的知识库 ==========
class _MyLibrariesCard extends StatelessWidget {
  const _MyLibrariesCard({
    required this.libraries,
    required this.onOpenLibrary,
  });

  final List<KnowledgeLibraryStudySummary> libraries;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '我的知识库',
      actionLabel: '全部知识库',
      onAction: onOpenLibrary,
      child: libraries.isEmpty
          ? _EmptyHint(
              icon: Icons.collections_bookmark_rounded,
              text: '还没有知识库，导入资料时会自动建立。',
              actionLabel: '去知识库',
              onAction: onOpenLibrary,
            )
          : Column(
              children: [
                for (var index = 0; index < libraries.length; index++) ...[
                  if (index > 0) const SizedBox(height: 12),
                  _LibrarySummaryTile(
                    summary: libraries[index],
                    onTap: onOpenLibrary,
                  ),
                ],
              ],
            ),
    );
  }
}

class _LibrarySummaryTile extends StatelessWidget {
  const _LibrarySummaryTile({required this.summary, required this.onTap});

  final KnowledgeLibraryStudySummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 46,
                child: KnowledgeBookCover(
                  title: '',
                  theme: summary.coverTheme,
                  color: summary.coverColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      summary.hasContent
                          ? '${summary.conceptCount} 个知识点 · ${summary.questionCount} 道题'
                          : '还没有学习内容',
                      style: AppTextStyles.caption(context).copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (summary.hasContent) ...[
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: (summary.progress / 100).clamp(0.0, 1.0),
                                minHeight: 5,
                                color: AppColors.primary,
                                backgroundColor: AppColors.surfaceMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${summary.progress}%',
                            style: AppTextStyles.caption(context).copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========== 搜索 ==========
class _StudySearchSheet extends StatefulWidget {
  const _StudySearchSheet({
    required this.repository,
    required this.userId,
    required this.onOpen,
  });

  final KnowledgeLibraryRepository repository;
  final int userId;
  final ValueChanged<StudySearchHit> onOpen;

  @override
  State<_StudySearchSheet> createState() => _StudySearchSheetState();
}

class _StudySearchSheetState extends State<_StudySearchSheet> {
  final _controller = TextEditingController();
  Future<List<StudySearchHit>>? _future;
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    final keyword = value.trim();
    setState(() {
      _keyword = keyword;
      _future = keyword.isEmpty
          ? null
          : widget.repository.searchStudyContent(
              userId: widget.userId,
              query: keyword,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('搜索学习内容', style: AppTextStyles.h2(context)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _search,
            decoration: const InputDecoration(
              hintText: '搜索知识点、练习题或资料',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: _buildResults(context),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final future = _future;
    if (future == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '输入关键词，在知识点、练习题和资料中查找。',
          style: AppTextStyles.bodySmall(context),
        ),
      );
    }
    return FutureBuilder<List<StudySearchHit>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Text('搜索失败：${snapshot.error}', style: AppTextStyles.bodySmall(context));
        }
        final hits = snapshot.data ?? const <StudySearchHit>[];
        if (hits.isEmpty) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '没有找到与“$_keyword”相关的内容。',
              style: AppTextStyles.bodySmall(context),
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: hits.length,
          itemBuilder: (context, index) {
            final hit = hits[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  switch (hit.kind) {
                    '练习题' => Icons.edit_note_rounded,
                    '资料' => Icons.description_rounded,
                    _ => Icons.psychology_alt_rounded,
                  },
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              title: Text(
                hit.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(hit.subtitle, maxLines: 1),
              onTap: () => widget.onOpen(hit),
            );
          },
        );
      },
    );
  }
}

// ========== 共用组件 ==========
enum _TagTone { primary, warning }

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.tone});

  final String label;
  final _TagTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      _TagTone.warning => (const Color(0xFFFEF3E7), AppColors.accentOrange),
      _TagTone.primary => (AppColors.primarySoft, AppColors.primaryDark),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: PremiumSectionHeader(title: title, subtitle: subtitle),
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall(context).copyWith(fontSize: 13),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                side: const BorderSide(color: AppColors.primaryLight),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
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
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== 数据模型 ==========
enum _ImportAction { gallery, document }

enum _RecommendationKind { concept, practice }

class _HomeRecommendation {
  const _HomeRecommendation({
    required this.kind,
    required this.title,
    required this.badge,
    required this.reason,
    required this.mastery,
    this.conceptId,
    this.documentId,
    this.questionIds = const [],
  });

  final _RecommendationKind kind;
  final String title, badge, reason;
  final int mastery;
  final int? conceptId, documentId;
  final List<int> questionIds;

  /// 薄弱提升只看掌握度偏低的知识点，以及还有错题没清的练习。
  bool get weak => kind == _RecommendationKind.concept
      ? mastery < 60
      : questionIds.isNotEmpty;

  factory _HomeRecommendation.fromConcept(ReviewRecommendation item) {
    return _HomeRecommendation(
      kind: _RecommendationKind.concept,
      title: item.name,
      badge: '知识点',
      reason: item.libraryName.isEmpty
          ? item.reason
          : '${item.libraryName} · ${item.reason}',
      mastery: item.masteryScore,
      conceptId: item.conceptId,
      documentId: item.documentId,
    );
  }

  factory _HomeRecommendation.fromBacklog(PracticeBacklog item) {
    final parts = <String>[
      if (item.wrongCount > 0) '${item.wrongCount} 道错题待订正',
      if (item.overdueCount > 0) '${item.overdueCount} 道练习已到期',
    ];
    final title = item.documentTitle.isEmpty ? '未命名资料' : item.documentTitle;
    return _HomeRecommendation(
      kind: _RecommendationKind.practice,
      title: title,
      badge: '练习',
      reason: parts.isEmpty
          ? '集中练习这批题，巩固当前进度。'
          : '${parts.join('，')}，建议集中突破。',
      mastery: 0,
      documentId: item.documentId,
      questionIds: item.questionIds,
    );
  }
}

class _Notice {
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title, detail;
  final VoidCallback onTap;
}

class _HomeData {
  const _HomeData({
    required this.user,
    required this.dashboard,
    required this.libraries,
    required this.recommendations,
    required this.todayTaskCount,
  });

  final UserProfile user;
  final LearningDashboard dashboard;
  final List<KnowledgeLibraryStudySummary> libraries;
  final List<_HomeRecommendation> recommendations;
  final int todayTaskCount;

  /// 首页只展示最近使用的几个知识库，但掌握度按全部知识库加权计算。
  List<KnowledgeLibraryStudySummary> get recentLibraries =>
      libraries.take(3).toList(growable: false);

  /// 与“我的知识库”用同一套口径：按内容量加权平均的掌握度。
  int? get masteryPercent {
    var weighted = 0;
    var total = 0;
    for (final library in libraries) {
      final size = library.conceptCount + library.questionCount;
      if (size == 0) continue;
      weighted += library.progress * size;
      total += size;
    }
    if (total == 0) return null;
    return (weighted / total).round().clamp(0, 100);
  }
}

String _greeting(DateTime now) {
  final hour = now.hour;
  if (hour < 6) return '夜深了';
  if (hour < 11) return '早上好';
  if (hour < 14) return '中午好';
  if (hour < 18) return '下午好';
  return '晚上好';
}
