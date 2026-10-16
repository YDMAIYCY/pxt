import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/models/ai_generation_task_record.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/source_document_repository.dart';
import '../../../learning/learning_events.dart';
import '../../../learning/learning_task_repository.dart';
import '../../theme/app_theme.dart';
import '../document_detail_page.dart';
import '../learning_concept_page.dart';
import '../library_practice_page.dart';
import '../practice_review_page.dart';
import '../wrong_question_page.dart';

const _taskBlue = Color(0xFF3068E9);
const _taskBackground = Color(0xFFF7F9FC);

class TasksTabPage extends StatefulWidget {
  const TasksTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.aiGenerationRepository,
    this.learningTaskRepository,
    this.refreshVersion = 0,
    this.refreshListenable,
    this.activeTabListenable,
    this.tabIndex,
    this.onDataChanged,
    this.onStartFocus,
    super.key,
  });

  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final LearningTaskRepository? learningTaskRepository;
  final int refreshVersion;
  final ValueListenable<int>? refreshListenable;
  final ValueListenable<int>? activeTabListenable;
  final int? tabIndex;
  final VoidCallback? onDataChanged;
  final ValueChanged<int>? onStartFocus;

  @override
  State<TasksTabPage> createState() => _TasksTabPageState();
}

class _TasksTabPageState extends State<TasksTabPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final LearningTaskRepository _taskRepository;
  late Future<LearningDashboard> _future;
  late int _handledRefreshVersion;
  int? _userId;
  bool _reloadScheduled = false;
  bool _notifying = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _taskRepository = widget.learningTaskRepository ?? LearningTaskRepository();
    _handledRefreshVersion = widget.refreshVersion;
    widget.refreshListenable?.addListener(_handleExternalRefresh);
    widget.activeTabListenable?.addListener(_handleExternalRefresh);
    LearningEvents.changed.addListener(_handleExternalRefresh);
    _future = _loadData();
  }

  @override
  void didUpdateWidget(covariant TasksTabPage oldWidget) {
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
    LearningEvents.changed.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  void _handleExternalRefresh() {
    if (_notifying || _busy) return;
    final tabIndex = widget.tabIndex;
    final activeTab = widget.activeTabListenable?.value;
    if (tabIndex == null || activeTab == null || activeTab == tabIndex) {
      _scheduleReload();
    }
  }

  void _scheduleReload() {
    if (!mounted || _reloadScheduled) return;
    _reloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reloadScheduled = false;
      _refresh();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<LearningDashboard> _loadData() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) throw StateError('登录状态已失效');
    _userId = user.id;
    return _taskRepository.dashboard(user.id);
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    // FutureBuilder renders load failures, including failed pull-to-refresh.
    try {
      await future;
    } catch (_) {}
  }

  Future<void> _afterDataChanged() async {
    if (!mounted) return;
    _notifying = true;
    try {
      LearningEvents.notify();
      widget.onDataChanged?.call();
    } finally {
      _notifying = false;
    }
    if (mounted) await _refresh();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _afterDataChanged();
    } catch (error) {
      _message('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openTaskList(TaskListKind kind) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskListPage(
          kind: kind,
          authRepository: _authRepository,
          sourceDocumentRepository: _sourceDocumentRepository,
          aiGenerationRepository: _aiGenerationRepository,
          onDataChanged: widget.onDataChanged,
        ),
      ),
    );
    await _afterDataChanged();
  }

  Future<void> _study(LearningTask task) async {
    Widget? page;
    if (task.questionId != null) {
      page = LibraryPracticePage(
        documentId: task.documentId,
        initialConceptId: task.conceptId,
        initialQuestionId: task.questionId,
        questionIds: [task.questionId!],
      );
    } else if (task.conceptId != null) {
      page = LearningConceptPage(conceptId: task.conceptId!);
    } else if (task.documentId != null) {
      page = DocumentDetailPage(documentId: task.documentId!);
    }
    if (page == null) {
      if (!task.active) {
        _message('这项任务${task.statusLabel}');
        return;
      }
      await _mutate(() async {
        await _taskRepository.setStatus(_userId!, task.id, 'in_progress');
        _message('已开始学习，可从任务菜单进入专注或记录完成');
      });
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page!));
    await _afterDataChanged();
  }

  Future<void> _openRecommendation(ReviewRecommendation item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LearningConceptPage(conceptId: item.conceptId),
      ),
    );
    await _afterDataChanged();
  }

  Future<void> _showTaskActions(LearningTask task) async {
    if (_busy) return;
    final action = await showModalBottomSheet<_LearningAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.menu_book_outlined,
                    color: _taskBlue,
                  ),
                  title: const Text('直接学习'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _LearningAction.study),
                ),
                if (task.active) ...[
                  ListTile(
                    leading: const Icon(Icons.timer_outlined, color: _taskBlue),
                    title: const Text('专注学习'),
                    subtitle: widget.onStartFocus == null
                        ? const Text('专注入口暂不可用')
                        : null,
                    enabled: widget.onStartFocus != null,
                    onTap: () =>
                        Navigator.pop(sheetContext, _LearningAction.focus),
                  ),
                  ListTile(
                    leading: Icon(
                      task.status == 'paused'
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    title: Text(task.status == 'paused' ? '继续任务' : '暂停任务'),
                    onTap: () => Navigator.pop(
                      sheetContext,
                      _LearningAction.togglePause,
                    ),
                  ),
                  if (task.kind == 'personal' || task.kind == 'concept_review')
                    ListTile(
                      leading: const Icon(Icons.check_circle_outline_rounded),
                      title: const Text('手动完成'),
                      onTap: () =>
                          Navigator.pop(sheetContext, _LearningAction.complete),
                    ),
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('推迟任务'),
                    onTap: () =>
                        Navigator.pop(sheetContext, _LearningAction.postpone),
                  ),
                  ListTile(
                    leading: const Icon(Icons.close_rounded),
                    title: const Text('取消任务'),
                    onTap: () =>
                        Navigator.pop(sheetContext, _LearningAction.cancel),
                  ),
                ],
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.error,
                  ),
                  title: const Text(
                    '删除任务',
                    style: TextStyle(color: AppColors.error),
                  ),
                  onTap: () =>
                      Navigator.pop(sheetContext, _LearningAction.delete),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _LearningAction.study:
        await _study(task);
      case _LearningAction.focus:
        widget.onStartFocus?.call(task.id);
      case _LearningAction.togglePause:
        await _setStatus(
          task,
          task.status == 'paused' ? 'in_progress' : 'paused',
        );
      case _LearningAction.complete:
        await _setStatus(task, 'completed');
      case _LearningAction.cancel:
        await _setStatus(task, 'cancelled');
      case _LearningAction.postpone:
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day + 1);
        final currentDue = task.dueAt?.toLocal();
        final date = await showDatePicker(
          context: context,
          initialDate: currentDue != null && currentDue.isAfter(tomorrow)
              ? currentDue
              : tomorrow,
          firstDate: tomorrow,
          lastDate: DateTime(now.year + 10, 12, 31),
        );
        if (date != null && mounted) {
          await _mutate(
            () => _taskRepository.setStatus(
              _userId!,
              task.id,
              task.status,
              dueAt: DateTime(date.year, date.month, date.day, 23, 59),
            ),
          );
        }
      case _LearningAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除任务？'),
            content: Text('确定删除“${task.title}”？学习资料和答题记录会保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('保留'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) await _setStatus(task, 'deleted');
    }
  }

  Future<void> _setStatus(LearningTask task, String status) =>
      _mutate(() => _taskRepository.setStatus(_userId!, task.id, status));

  Future<void> _createTask() async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => const _CreateLearningTaskDialog(),
    );
    if (result == null || !mounted) return;
    final operationKey = 'personal-${DateTime.now().microsecondsSinceEpoch}';
    await _mutate(() async {
      await _taskRepository.create(
        userId: _userId!,
        title: result.$1,
        estimatedPomodoros: result.$2,
        operationKey: operationKey,
      );
    });
  }

  Future<void> _showAllTasks() async {
    var future = _taskRepository.tasks(_userId!, includeFinished: true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '全部任务',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<LearningTask>>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _StatePanel(
                          icon: Icons.error_outline,
                          title: '任务加载失败',
                          description: '请稍后重试。',
                          onPressed: () async => setSheetState(() {
                            future = _taskRepository.tasks(
                              _userId!,
                              includeFinished: true,
                            );
                          }),
                        );
                      }
                      final tasks = snapshot.data!;
                      if (tasks.isEmpty) {
                        return const Center(child: Text('还没有任务，试试新建一个学习目标'));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemCount: tasks.length,
                        itemBuilder: (_, index) => _LearningTaskCard(
                          task: tasks[index],
                          onTap: () async {
                            await _showTaskActions(tasks[index]);
                            if (sheetContext.mounted) {
                              setSheetState(() {
                                future = _taskRepository.tasks(
                                  _userId!,
                                  includeFinished: true,
                                );
                              });
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _taskBackground,
      child: FutureBuilder<LearningDashboard>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final now = DateTime.now();
          final tomorrow = DateTime(now.year, now.month, now.day + 1);
          final todayTasks =
              data?.tasks
                  .where(
                    (task) =>
                        task.active &&
                        (task.dueAt == null ||
                            task.dueAt!.toLocal().isBefore(tomorrow)),
                  )
                  .toList() ??
              <LearningTask>[];
          return RefreshIndicator(
            color: _taskBlue,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '任务中心',
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '把每一次学习，变成看得见的进步',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'AI 处理列表',
                      onPressed: () => _openTaskList(TaskListKind.activeFlow),
                      icon: const Icon(
                        Icons.auto_awesome_outlined,
                        color: _taskBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    data == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: CircularProgressIndicator(color: _taskBlue),
                    ),
                  )
                else if (snapshot.hasError)
                  _StatePanel(
                    icon: Icons.error_outline_rounded,
                    title: '任务中心加载失败',
                    description: '请检查登录状态后重试。',
                    onPressed: _refresh,
                  )
                else if (data != null) ...[
                  _LearningStats(
                    data: data,
                    onOpenList: _openTaskList,
                    onOpenTasks: _showAllTasks,
                  ),
                  const SizedBox(height: 24),
                  _LearningSectionHeader(
                    title: '今日任务',
                    action: '全部任务',
                    onTap: _showAllTasks,
                  ),
                  const SizedBox(height: 12),
                  if (todayTasks.isEmpty)
                    const _EmptyHint(text: '今天暂无待办任务\n新建一个学习目标，或从下方添加复习计划')
                  else
                    ...todayTasks.map(
                      (task) => _LearningTaskCard(
                        task: task,
                        onTap: _busy ? null : () => _showTaskActions(task),
                      ),
                    ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _taskBlue,
                      side: const BorderSide(color: Color(0xFFCFDCFB)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _busy ? null : _createTask,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('新建学习任务'),
                  ),
                  const SizedBox(height: 26),
                  const _LearningSectionHeader(title: '推荐复习'),
                  const SizedBox(height: 6),
                  const Text(
                    '根据掌握情况，为你安排下一步',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (data.recommendations.isEmpty)
                    const _EmptyHint(text: '暂无推荐复习\n学习和答题后，会在这里推荐需要巩固的知识点')
                  else
                    ...data.recommendations.map(
                      (item) => _ReviewRecommendationCard(
                        item: item,
                        onReview: () => _openRecommendation(item),
                        onAdd: _busy
                            ? null
                            : () => _mutate(
                                () => _taskRepository.addConceptReview(
                                  _userId!,
                                  item.conceptId,
                                ),
                              ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _LearningAction {
  study,
  focus,
  togglePause,
  complete,
  postpone,
  cancel,
  delete,
}

class _CreateLearningTaskDialog extends StatefulWidget {
  const _CreateLearningTaskDialog();

  @override
  State<_CreateLearningTaskDialog> createState() =>
      _CreateLearningTaskDialogState();
}

class _CreateLearningTaskDialogState extends State<_CreateLearningTaskDialog> {
  final _title = TextEditingController();
  int _pomodoros = 1;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建学习任务'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            maxLength: 100,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '任务名称',
              hintText: '例如：复习第一章',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          const Text('预计番茄数', style: TextStyle(fontWeight: FontWeight.w600)),
          Row(
            children: [
              IconButton(
                tooltip: '减少番茄数',
                onPressed: _pomodoros > 1
                    ? () => setState(() => _pomodoros--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Text(
                  '$_pomodoros',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    color: _taskBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '增加番茄数',
                onPressed: _pomodoros < 99
                    ? () => setState(() => _pomodoros++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: _taskBlue),
        onPressed: () {
          final title = _title.text.trim();
          if (title.isEmpty) {
            setState(() => _error = '请输入任务名称');
            return;
          }
          Navigator.pop(context, (title, _pomodoros));
        },
        child: const Text('创建任务'),
      ),
    ],
  );
}

class _LearningSectionHeader extends StatelessWidget {
  const _LearningSectionHeader({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: _taskBlue),
          child: Text(action!),
        ),
    ],
  );
}

class _LearningStats extends StatelessWidget {
  const _LearningStats({
    required this.data,
    required this.onOpenList,
    required this.onOpenTasks,
  });
  final LearningDashboard data;
  final ValueChanged<TaskListKind> onOpenList;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        '待刷练习',
        data.pendingPractice,
        Icons.edit_note_rounded,
        _taskBlue,
        () => onOpenList(TaskListKind.todayPractice),
      ),
      (
        '逾期练习',
        data.overduePractice,
        Icons.event_busy_outlined,
        const Color(0xFFE39135),
        () => onOpenList(TaskListKind.overduePractice),
      ),
      (
        '待处理错题',
        data.wrongQuestions,
        Icons.auto_stories_outlined,
        const Color(0xFFE06476),
        () => onOpenList(TaskListKind.wrongQuestions),
      ),
      (
        '进行中',
        data.inProgress,
        Icons.timelapse_rounded,
        const Color(0xFF6B62CE),
        onOpenTasks,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: width,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: stat.$5,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(stat.$3, color: stat.$4, size: 24),
                            const SizedBox(height: 12),
                            Text(
                              '${stat.$2}',
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                color: stat.$4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              stat.$1,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _LearningTaskCard extends StatelessWidget {
  const _LearningTaskCard({required this.task, this.onTap});
  final LearningTask task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final due = task.dueAt?.toLocal();
    final overdue = task.active && due != null && due.isBefore(DateTime.now());
    final source = [
      task.libraryName,
      task.documentTitle,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final progress = task.progress.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF3FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        task.questionId != null
                            ? Icons.quiz_outlined
                            : task.conceptId != null
                            ? Icons.psychology_outlined
                            : Icons.checklist_rounded,
                        size: 22,
                        color: _taskBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            source.isEmpty ? task.kindLabel : source,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      '${task.kindLabel} · ${task.statusLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _taskBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '已专注 ${task.focusedSeconds ~/ 60} 分钟 / 预计 ${task.estimatedPomodoros} 个番茄',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(8),
                  color: _taskBlue,
                  backgroundColor: const Color(0xFFEDF1F7),
                ),
                const SizedBox(height: 9),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    Text(
                      task.totalUnits > 0
                          ? '${task.completedUnits}/${task.totalUnits} · ${(progress * 100).round()}%'
                          : '${(progress * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      due == null
                          ? '未设截止时间'
                          : '${overdue ? '已逾期' : '截止'} ${_formatTime(due)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: overdue
                            ? AppColors.error
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewRecommendationCard extends StatelessWidget {
  const _ReviewRecommendationCard({
    required this.item,
    required this.onReview,
    this.onAdd,
  });
  final ReviewRecommendation item;
  final VoidCallback onReview;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onReview,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '来源：${item.libraryName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '掌握度 ${item.masteryScore}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _taskBlue,
                ),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (item.masteryScore / 100).clamp(0, 1),
                color: _taskBlue,
                backgroundColor: const Color(0xFFEDF1F7),
                borderRadius: BorderRadius.circular(8),
                minHeight: 4,
              ),
              const SizedBox(height: 12),
              Text(
                item.reason,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: onAdd,
                    style: TextButton.styleFrom(foregroundColor: _taskBlue),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('加入任务'),
                  ),
                  FilledButton(
                    onPressed: onReview,
                    style: FilledButton.styleFrom(backgroundColor: _taskBlue),
                    child: const Text('开始复习'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ========== Task List Page ==========
class TaskListPage extends StatefulWidget {
  const TaskListPage({
    required this.kind,
    required this.authRepository,
    required this.sourceDocumentRepository,
    required this.aiGenerationRepository,
    this.onDataChanged,
    super.key,
  });
  final TaskListKind kind;
  final AuthRepository authRepository;
  final SourceDocumentRepository sourceDocumentRepository;
  final AiGenerationRepository aiGenerationRepository;
  final VoidCallback? onDataChanged;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  late Future<_TaskListData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_TaskListData> _loadData() async {
    await widget.authRepository.ensureInitialized();
    final user = await widget.authRepository.getCurrentUserProfile();
    if (user == null) throw StateError('登录状态已失效');
    final documents = await widget.sourceDocumentRepository
        .fetchAllSourceDocuments(userId: user.id, limit: 300);

    switch (widget.kind) {
      case TaskListKind.todayPractice:
        return _TaskListData(
          documents: documents,
          questions: await widget.aiGenerationRepository
              .fetchTodayPracticeQuestionsByUser(userId: user.id, limit: 300),
        );
      case TaskListKind.overduePractice:
        return _TaskListData(
          documents: documents,
          questions: await widget.aiGenerationRepository
              .fetchOverduePracticeQuestionsByUser(userId: user.id, limit: 300),
        );
      case TaskListKind.wrongQuestions:
        return _TaskListData(
          documents: documents,
          questions: await widget.aiGenerationRepository
              .fetchPracticeQuestionsByUser(
                userId: user.id,
                reviewStatus: PracticeQuestionReviewStatus.wrong,
                limit: 300,
              ),
        );
      case TaskListKind.activeFlow:
        return _TaskListData(
          documents: documents,
          aiTasks: await widget.aiGenerationRepository.fetchAiTasksByUser(
            userId: user.id,
            limit: 300,
          ),
        );
      case TaskListKind.masteredQuestions:
        return _TaskListData(
          documents: documents,
          questions: await widget.aiGenerationRepository
              .fetchPracticeQuestionsByUser(
                userId: user.id,
                reviewStatus: PracticeQuestionReviewStatus.mastered,
                limit: 300,
              ),
        );
    }
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _afterDataChanged() async {
    widget.onDataChanged?.call();
    await _refresh();
  }

  Future<void> _openPractice([int? questionId]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeReviewPage(
          initialQuestionId: questionId,
          authRepository: widget.authRepository,
          aiGenerationRepository: widget.aiGenerationRepository,
        ),
      ),
    );
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openWrongQuestion(PracticeQuestionWithDocument item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WrongQuestionPage(
          item: item,
          aiGenerationRepository: widget.aiGenerationRepository,
          authRepository: widget.authRepository,
        ),
      ),
    );
    if (mounted) await _afterDataChanged();
  }

  Future<void> _openDocument(int documentId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailPage(documentId: documentId),
      ),
    );
    if (mounted) await _afterDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_titleOf(widget.kind))),
      body: FutureBuilder<_TaskListData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StatePanel(
              icon: Icons.error_outline_rounded,
              title: '列表加载失败',
              description: '请稍后重试。',
              onPressed: _refresh,
            );
          }
          final data = snapshot.data ?? const _TaskListData();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: _buildItems(data),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildItems(_TaskListData data) {
    switch (widget.kind) {
      case TaskListKind.todayPractice:
        if (data.questions.isEmpty) {
          return [const _EmptyHint(text: '暂无待刷练习题。生成练习题后会出现在这里。')];
        }
        return _buildQuestionGroups(
          data,
          status: '待刷',
          statusColor: AppColors.accentOrange,
          onTap: (item) => _openPractice(item.question.id),
        );
      case TaskListKind.overduePractice:
        if (data.questions.isEmpty) return [const _EmptyHint(text: '暂无逾期练习题。')];
        return _buildQuestionGroups(
          data,
          status: '逾期',
          statusColor: AppColors.error,
          onTap: (item) => _openPractice(item.question.id),
        );
      case TaskListKind.wrongQuestions:
        if (data.questions.isEmpty) return [const _EmptyHint(text: '暂无待处理错题。')];
        return _buildQuestionGroups(
          data,
          status: '待处理',
          statusColor: AppColors.warning,
          subtitleOf: (item) => '${item.documentTitle} / 正确答案可点入查看',
          onTap: _openWrongQuestion,
        );
      case TaskListKind.activeFlow:
        final groups = _buildActiveFlowGroups(data);
        if (groups.isEmpty) {
          return [const _EmptyHint(text: '暂无进行中的 OCR 或 AI 任务。')];
        }
        return groups;
      case TaskListKind.masteredQuestions:
        if (data.questions.isEmpty) return [const _EmptyHint(text: '暂无已掌握题目。')];
        return _buildQuestionGroups(
          data,
          status: '已掌握',
          statusColor: AppColors.success,
          subtitleOf: (item) =>
              '${item.documentTitle} / 答案：${item.question.answerText ?? '暂无'}',
          onTap: (item) => _openDocument(item.question.documentId),
        );
    }
  }

  List<Widget> _buildQuestionGroups(
    _TaskListData data, {
    required String status,
    required Color statusColor,
    required ValueChanged<PracticeQuestionWithDocument> onTap,
    String Function(PracticeQuestionWithDocument item)? subtitleOf,
  }) {
    return _groupQuestionsByImport(data)
        .map(
          (group) => _TaskImportGroupTile(
            group: group,
            children: group.questions
                .map(
                  (item) => _TaskTile(
                    title: item.question.questionText,
                    subtitle: subtitleOf?.call(item) ?? _questionMeta(item),
                    status: status,
                    statusColor: statusColor,
                    onTap: () => onTap(item),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  List<Widget> _buildActiveFlowGroups(_TaskListData data) {
    return _groupActiveFlowByImport(data)
        .map(
          (group) => _TaskImportGroupTile(
            group: group,
            children: [
              ...group.documents
                  .where((d) => d.ocrStatus != SourceDocumentOcrStatus.success)
                  .map(
                    (d) => _TaskTile(
                      title: d.title,
                      subtitle: 'OCR ${d.ocrStatusLabel}',
                      status: _statusLabel(d.ocrStatus),
                      statusColor: _statusColor(d.ocrStatus),
                      onTap: () => _openDocument(d.id),
                    ),
                  ),
              ...group.aiTasks
                  .where((t) => t.status != AiTaskStatus.completed)
                  .map(
                    (t) => _TaskTile(
                      title: '${t.documentTitle} -> ${t.taskLabel}',
                      subtitle: t.errorMessage?.isNotEmpty == true
                          ? t.errorMessage!
                          : _formatTime(t.updatedAt),
                      status: _statusLabel(t.status),
                      statusColor: _statusColor(t.status),
                      onTap: () => _openDocument(t.documentId),
                    ),
                  ),
            ],
          ),
        )
        .toList(growable: false);
  }

  List<_TaskImportGroup> _groupQuestionsByImport(_TaskListData data) {
    final documentsById = {
      for (final document in data.documents) document.id: document,
    };
    final grouped = <String, _MutableTaskImportGroup>{};
    for (final item in data.questions) {
      final document = documentsById[item.question.documentId];
      final key = _taskGroupKey(document, item.question.documentId);
      final group = grouped.putIfAbsent(
        key,
        () => _MutableTaskImportGroup.fromDocument(
          document,
          fallbackTitle: item.documentTitle,
        ),
      );
      group.questions.add(item);
    }
    return _finalizeTaskGroups(grouped.values);
  }

  List<_TaskImportGroup> _groupActiveFlowByImport(_TaskListData data) {
    final documentsById = {
      for (final document in data.documents) document.id: document,
    };
    final grouped = <String, _MutableTaskImportGroup>{};
    for (final document in data.documents.where(
      (item) => item.ocrStatus != SourceDocumentOcrStatus.success,
    )) {
      final key = _taskGroupKey(document, document.id);
      final group = grouped.putIfAbsent(
        key,
        () => _MutableTaskImportGroup.fromDocument(document),
      );
      group.documents.add(document);
    }
    for (final task in data.aiTasks.where(
      (item) => item.status != AiTaskStatus.completed,
    )) {
      final document = documentsById[task.documentId];
      final key = _taskGroupKey(document, task.documentId);
      final group = grouped.putIfAbsent(
        key,
        () => _MutableTaskImportGroup.fromDocument(
          document,
          fallbackTitle: task.documentTitle,
          fallbackTime: task.updatedAt,
        ),
      );
      group.aiTasks.add(task);
    }
    return _finalizeTaskGroups(grouped.values);
  }

  String _taskGroupKey(SourceDocumentRecord? document, int documentId) {
    final batchId = document?.batchId;
    return batchId == null ? 'document:$documentId' : 'batch:$batchId';
  }

  List<_TaskImportGroup> _finalizeTaskGroups(
    Iterable<_MutableTaskImportGroup> groups,
  ) {
    final result = groups
        .map((group) => group.toImmutable())
        .where((group) => group.itemCount > 0)
        .toList(growable: false);
    return result..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

// ========== Task Import Groups ==========
class _TaskImportGroupTile extends StatelessWidget {
  const _TaskImportGroupTile({required this.group, required this.children});

  final _TaskImportGroup group;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: AppColors.primary,
            ),
          ),
          title: Text(
            group.title,
            maxLines: 3,
            softWrap: true,
            style: AppTextStyles.h3(
              context,
            ).copyWith(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              group.subtitle,
              maxLines: 3,
              softWrap: true,
              style: AppTextStyles.bodySmall(context).copyWith(
                color: AppColors.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.itemCount}',
                  style: AppTextStyles.bodySmall(context).copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
          children: children,
        ),
      ),
    );
  }
}

// ========== Task Tile ==========
class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    required this.onTap,
  });
  final String title, subtitle, status;
  final Color statusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 5,
                        softWrap: true,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 4,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
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
  final String title, description;
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
              style: FilledButton.styleFrom(backgroundColor: _taskBlue),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== Data models ==========
class _MutableTaskImportGroup {
  _MutableTaskImportGroup({
    required this.key,
    required this.title,
    required this.createdAt,
    required this.sourceLabel,
  });

  factory _MutableTaskImportGroup.fromDocument(
    SourceDocumentRecord? document, {
    String? fallbackTitle,
    DateTime? fallbackTime,
  }) {
    return _MutableTaskImportGroup(
      key: document?.batchId == null
          ? 'document:${document?.id ?? fallbackTitle ?? 'unknown'}'
          : 'batch:${document!.batchId}',
      title: document?.batchId == null
          ? (document?.title ?? fallbackTitle ?? '未命名资料')
          : '学习包：${document!.title}',
      createdAt: document?.createdAt ?? fallbackTime ?? DateTime.now(),
      sourceLabel: document?.sourceTypeLabel ?? '资料',
    );
  }

  final String key;
  final String title;
  final DateTime createdAt;
  final String sourceLabel;
  final List<SourceDocumentRecord> documents = <SourceDocumentRecord>[];
  final List<AiTaskWithDocument> aiTasks = <AiTaskWithDocument>[];
  final List<PracticeQuestionWithDocument> questions =
      <PracticeQuestionWithDocument>[];

  _TaskImportGroup toImmutable() {
    return _TaskImportGroup(
      key: key,
      title: title,
      subtitle:
          '$sourceLabel / ${_formatTime(createdAt)} / ${documents.length + aiTasks.length + questions.length} 项',
      createdAt: createdAt,
      documents: documents,
      aiTasks: aiTasks,
      questions: questions,
    );
  }
}

class _TaskImportGroup {
  const _TaskImportGroup({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.documents,
    required this.aiTasks,
    required this.questions,
  });

  final String key;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final List<SourceDocumentRecord> documents;
  final List<AiTaskWithDocument> aiTasks;
  final List<PracticeQuestionWithDocument> questions;

  int get itemCount => documents.length + aiTasks.length + questions.length;
}

class _TaskListData {
  const _TaskListData({
    this.documents = const <SourceDocumentRecord>[],
    this.aiTasks = const <AiTaskWithDocument>[],
    this.questions = const <PracticeQuestionWithDocument>[],
  });

  final List<SourceDocumentRecord> documents;
  final List<AiTaskWithDocument> aiTasks;
  final List<PracticeQuestionWithDocument> questions;
}

enum TaskListKind {
  todayPractice,
  overduePractice,
  wrongQuestions,
  activeFlow,
  masteredQuestions,
}

String _titleOf(TaskListKind kind) {
  switch (kind) {
    case TaskListKind.todayPractice:
      return '今日待刷练习题';
    case TaskListKind.overduePractice:
      return '逾期练习';
    case TaskListKind.wrongQuestions:
      return '待处理错题';
    case TaskListKind.activeFlow:
      return '所有资料与任务';
    case TaskListKind.masteredQuestions:
      return '已掌握题目';
  }
}

String _questionMeta(PracticeQuestionWithDocument item) {
  final question = item.question;
  final parts = <String>[
    item.documentTitle,
    '掌握度 ${question.masteryScore}',
    '错 ${question.wrongCount} 次',
  ];
  final nextReviewAt = question.nextReviewAt;
  if (nextReviewAt != null) parts.add('下次 ${_formatTime(nextReviewAt)}');
  return parts.join(' / ');
}

String _statusLabel(String status) {
  if (status == SourceDocumentOcrStatus.processing) return '进行中';
  if (status == SourceDocumentOcrStatus.needsReview) return '待校对';
  if (status == SourceDocumentOcrStatus.success) return '已完成';
  if (status == SourceDocumentOcrStatus.failed) return '失败';
  switch (status) {
    case AiTaskStatus.running:
      return '进行中';
    case AiTaskStatus.completed:
      return '已完成';
    case AiTaskStatus.failed:
      return '失败';
    case AiTaskStatus.pending:
    default:
      return '待处理';
  }
}

Color _statusColor(String status) {
  if (status == SourceDocumentOcrStatus.processing) return AppColors.info;
  if (status == SourceDocumentOcrStatus.needsReview) {
    return const Color(0xFFF59E0B);
  }
  if (status == SourceDocumentOcrStatus.success) return AppColors.success;
  if (status == SourceDocumentOcrStatus.failed) return AppColors.error;
  switch (status) {
    case AiTaskStatus.running:
      return AppColors.info;
    case AiTaskStatus.completed:
      return AppColors.success;
    case AiTaskStatus.failed:
      return AppColors.error;
    case AiTaskStatus.pending:
    default:
      return AppColors.warning;
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.month}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
