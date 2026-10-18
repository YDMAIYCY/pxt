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
import '../../widgets/app_kit.dart';
import '../../widgets/create_knowledge_library_dialog.dart';
import '../../widgets/knowledge_book_cover.dart';
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
    _authRepository =
        widget.authRepository ?? AuthRepository(database: widget.database);
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ??
        SourceDocumentRepository(database: widget.database);
    _knowledgeLibraryRepository =
        widget.knowledgeLibraryRepository ??
        KnowledgeLibraryRepository(database: widget.database);
    _learningTaskRepository =
        widget.learningTaskRepository ??
        LearningTaskRepository(database: widget.database);
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
        builder: (_) =>
            InterviewPreparePage(userId: userId, database: widget.database),
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
          return const AppSkeletonList(items: 3, height: 92);
        }
        if (snapshot.hasError) {
          return AppErrorState(
            icon: Icons.error_outline_rounded,
            title: '首页加载失败',
            description: '请检查网络后重试。',
            onRetry: _refresh,
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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HomeTopBar(
                        user: data.user,
                        onSearch: _openSearch,
                        onNotifications: () => _openNotifications(data),
                      ),
                      const SizedBox(height: 16),
                      // The one thing the user came for: what to do right now.
                      _HomeHero(
                        task: data.dashboard.tasks.firstOrNull,
                        onContinue: _openLearningTask,
                        onOpenTasks: () => _openTab(3),
                      ),
                      const SizedBox(height: 18),
                      _QuickActionsRow(
                        isImporting: _isImporting,
                        onCamera: () =>
                            _handleImageImport(ImageInputSource.camera),
                        onImport: _openImportSourceSheet,
                        onInterview: _openInterview,
                        onOpenAgent: _openQsClaw,
                      ),
                      const SizedBox(height: 20),
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
                      const SizedBox(height: 14),
                      _RecommendationCard(
                        recommendations: data.recommendations,
                        onOpen: _openRecommendation,
                        onOpenTasks: () => _openTab(3),
                      ),
                      const SizedBox(height: 14),
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

// ========== 顶部栏 ==========
// Deliberately compact: the greeting is context, not the headline. The
// headline is the hero below, so this stays one line plus two actions.
class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.user,
    required this.onSearch,
    required this.onNotifications,
  });

  final UserProfile user;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(DateTime.now()),
                style: AppTextStyles.overline(context),
              ),
              const SizedBox(height: 3),
              Text(
                user.primaryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _HeaderIconButton(
          icon: Icons.search_rounded,
          tooltip: '搜索学习内容',
          onTap: onSearch,
        ),
        const SizedBox(width: 8),
        _HeaderIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: '学习提醒',
          onTap: onNotifications,
        ),
      ],
    );
  }
}

// ========== 焦点区：当前任务 ==========
// The single focal surface of the page. It absorbs the greeting block and the
// old "当前任务" card so the page has one clear entry point instead of five
// equal-weight white cards.
class _HomeHero extends StatelessWidget {
  const _HomeHero({
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
    final minutes = (current?.focusedSeconds ?? 0) ~/ 60;
    final target = (current?.estimatedPomodoros ?? 0) * 25;
    final progress = target <= 0 ? 0.0 : (minutes / target).clamp(0.0, 1.0);
    final source = current == null
        ? ''
        : [
            current.libraryName,
            current.documentTitle,
          ].where((value) => value.trim().isNotEmpty).join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: current == null ? onOpenTasks : () => onContinue(current),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [AppShadows.cardSoft],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Stack(
              children: [
                // A faint brand glow keeps the surface from reading as a plain
                // white box without tinting the whole card again.
                Positioned(
                  right: -56,
                  top: -74,
                  child: IgnorePointer(
                    child: Container(
                      width: 196,
                      height: 196,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.primary.withValues(alpha: 0.10),
                            AppColors.primary.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 3,
                            height: 13,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            current == null ? '今天的学习' : '继续上次学习',
                            style: AppTextStyles.label(context).copyWith(
                              color: AppColors.textSecondary,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          if (current != null)
                            AppTag(
                              label: current.kindLabel,
                              accent: AppColors.primary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Text(
                        current?.title ?? '安排今天的学习',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h2(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700, height: 1.28),
                      ),
                      if (source.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            const Icon(
                              Icons.menu_book_rounded,
                              size: 13,
                              color: AppColors.textQuiet,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: AppProgressBar(
                                        value: progress,
                                        accent: AppColors.primary,
                                        track: AppColors.surfaceMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${(progress * 100).round()}%',
                                      style: AppTextStyles.label(context)
                                          .copyWith(
                                            color: AppColors.primaryDark,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  minutes == 0
                                      ? '尚未开始'
                                      : '已专注 $minutes 分钟',
                                  style: AppTextStyles.caption(context),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          _HeroAction(
                            icon: current == null
                                ? Icons.add_rounded
                                : Icons.play_arrow_rounded,
                            tooltip: current == null ? '新建学习任务' : '继续学习',
                            onTap: current == null
                                ? onOpenTasks
                                : () => onContinue(current),
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
      ),
    );
  }
}

/// The one loud element of the hero: a filled circle that reads as "play".
class _HeroAction extends StatelessWidget {
  const _HeroAction({
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
        color: Colors.transparent,
        child: Ink(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: 26, color: AppColors.textOnPrimary),
          ),
        ),
      ),
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
    return AppCard.plain(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: '\u5b66\u4e60\u6982\u89c8',
            trailing: TextButton(
              onPressed: onOpenTasks,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: AppTextStyles.label(context),
              ),
              child: const Text('\u4efb\u52a1\u4e2d\u5fc3'),
            ),
          ),
          const SizedBox(height: 16),
          AppStatRow(
            tiles: [
              AppStatTile(
                icon: Icons.today_rounded,
                value: '$todayTaskCount',
                label: '\u4eca\u65e5\u4efb\u52a1',
                accent: AppColors.primary,
                muted: todayTaskCount == 0,
                onTap: onOpenTasks,
              ),
              AppStatTile(
                icon: Icons.report_problem_rounded,
                value: '$wrongQuestions',
                label: '\u5f85\u5904\u7406\u9519\u9898',
                accent: AppColors.error,
                muted: wrongQuestions == 0,
                onTap: onOpenWrong,
              ),
              AppStatTile(
                icon: Icons.schedule_rounded,
                value: '$overduePractice',
                label: '\u590d\u4e60\u5230\u671f',
                accent: AppColors.accentAmber,
                muted: overduePractice == 0,
                onTap: onOpenOverdue,
              ),
              AppStatTile(
                icon: Icons.insights_rounded,
                value: masteryPercent == null ? '\u2014' : '$masteryPercent%',
                label: '\u6574\u4f53\u638c\u63e3\u5ea6',
                accent: AppColors.accentMint,
                muted: masteryPercent == null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ========== 快捷操作 ==========
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
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
    // Deliberately no card wrapper. These are the page's primary verbs, and a
    // bare row stops the home page from being five stacked white boxes.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _QuickActionTile(
            imageAsset: AppAssets.quickCamera,
            iconAsset: AppAssets.iconCamera,
            label: '\u62cd\u7167\u8bc6\u522b',
            accent: AppColors.accentSky,
            onTap: isImporting ? null : onCamera,
          ),
        ),
        Expanded(
          child: _QuickActionTile(
            imageAsset: AppAssets.quickImport,
            iconAsset: AppAssets.iconAlbum,
            label: '\u5bfc\u5165\u8d44\u6599',
            accent: AppColors.accentMint,
            onTap: isImporting ? null : onImport,
          ),
        ),
        Expanded(
          child: _QuickActionTile(
            imageAsset: AppAssets.quickInterview,
            iconAsset: AppAssets.iconAi,
            label: 'AI \u9762\u8bd5',
            accent: AppColors.accentAmber,
            onTap: onInterview,
          ),
        ),
        Expanded(
          child: _QuickActionTile(
            avatarAsset: 'assets/images/eclaw_robot_avatar.png',
            label: '\u95ee EClaw',
            accent: AppColors.accentViolet,
            onTap: onOpenAgent,
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.label,
    required this.accent,
    required this.onTap,
    this.imageAsset,
    this.iconAsset,
    this.avatarAsset,
  });

  final String label;
  final Color accent;
  final VoidCallback? onTap;

  /// Full-colour 3D icon art that already carries its own rounded background.
  /// Preferred when present, so all four tiles share one icon language.
  final String? imageAsset;

  /// Flat vector fallback, used only if [imageAsset] is missing.
  final String? iconAsset;
  final String? avatarAsset;

  static const double _artSize = 52;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            children: [
              SizedBox(
                width: _artSize,
                height: _artSize,
                child: Opacity(
                  opacity: enabled ? 1 : 0.4,
                  child: imageAsset != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppRadii.cardSmall,
                          ),
                          child: Image.asset(
                            imageAsset!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _flatFallback(enabled),
                          ),
                        )
                      : _flatFallback(enabled),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall(context).copyWith(
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The pre-existing look: a tinted rounded square holding either the EClaw
  /// avatar or a flat vector glyph.
  Widget _flatFallback(bool enabled) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tintOf(accent, enabled ? 0.13 : 0.06),
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        border: Border.all(color: AppColors.tintOf(accent, 0.20)),
      ),
      alignment: Alignment.center,
      child: avatarAsset != null
          ? Padding(
              padding: const EdgeInsets.all(5),
              child: Image.asset(
                avatarAsset!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.smart_toy_rounded, size: 22, color: accent),
              ),
            )
          : SvgPicture.asset(
              iconAsset!,
              width: 23,
              height: 23,
              colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
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

    return AppCard.plain(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(title: '为你推荐'),
          const SizedBox(height: 14),
          AppSegmented<int>(
            value: _weakOnly ? 1 : 0,
            onChanged: (index) => setState(() => _weakOnly = index == 1),
            options: const [
              AppSegmentedOption(0, '今日推荐'),
              AppSegmentedOption(1, '薄弱提升'),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            AppEmptyState(
              compact: true,
              icon: Icons.lightbulb_outline_rounded,
              title: _weakOnly ? '没有明显薄弱的内容' : '还没有学习建议',
              description: _weakOnly
                  ? '保持现在的节奏就好。'
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
    final accent = isPractice ? AppColors.accentAmber : AppColors.accentViolet;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.tintOf(accent, 0.07),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final leading = Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.tintOf(accent, 0.16),
                    borderRadius: BorderRadius.circular(AppRadii.chipSmall),
                  ),
                  child: Icon(
                    isPractice
                        ? Icons.edit_note_rounded
                        : Icons.psychology_alt_rounded,
                    size: 20,
                    color: accent,
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
                            style: AppTextStyles.title(context),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AppTag(label: item.badge, accent: accent),
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
                    textStyle: AppTextStyles.label(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
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
                      Align(alignment: Alignment.centerRight, child: action),
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
    return AppCard.plain(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: '我的知识库',
            trailing: TextButton(
              onPressed: onOpenLibrary,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('全部'),
            ),
          ),
          const SizedBox(height: 14),
          if (libraries.isEmpty)
            AppEmptyState(
              compact: true,
              icon: Icons.collections_bookmark_rounded,
              title: '还没有知识库',
              description: '导入资料时会自动建立。',
              actionLabel: '去知识库',
              onAction: onOpenLibrary,
            )
          else
            // A horizontal strip of the real book covers. This is the app's
            // signature visual, so the home page surfaces it rather than
            // hiding it behind a tab.
            SizedBox(
              height: 166,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: libraries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) => _LibraryBookTile(
                  summary: libraries[index],
                  onTap: onOpenLibrary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LibraryBookTile extends StatelessWidget {
  const _LibraryBookTile({required this.summary, required this.onTap});

  final KnowledgeLibraryStudySummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reuses the existing cover widget untouched.
          KnowledgeBookCover(
            title: '',
            theme: summary.coverTheme,
            color: summary.coverColor,
            onTap: onTap,
          ),
          const SizedBox(height: 8),
          Text(
            summary.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall(
              context,
            ).copyWith(color: AppColors.textPrimary, height: 1.3),
          ),
          const SizedBox(height: 4),
          Text(
            summary.hasContent
                ? '${summary.conceptCount} 知识点 · ${summary.progress}%'
                : '还没有学习内容',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall(
              context,
            ).copyWith(color: AppColors.textQuiet, fontWeight: FontWeight.w500),
          ),
        ],
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
              hintText: '搜索',
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
          return Text(
            '搜索失败：${snapshot.error}',
            style: AppTextStyles.bodySmall(context),
          );
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
      reason: parts.isEmpty ? '集中练习这批题，巩固当前进度。' : '${parts.join('，')}，建议集中突破。',
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
