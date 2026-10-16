import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../database/auth_repository.dart';
import '../../../database/models/user_profile.dart';
import '../../../focus/models/pomodoro_task.dart';
import '../../../focus/models/pomodoro_record.dart';
import '../../../focus/models/checkin_record.dart';
import '../../../focus/repository/focus_repository.dart';
import '../../../learning/learning_events.dart';
import '../../../learning/learning_task_repository.dart';
import '../../theme/app_theme.dart';

const _focusBlue = Color(0xFF3068E9);
const _focusBackground = Color(0xFFF7F9FC);
const List<Color> _pieColors = [
  Color(0xFF3068E9),
  Color(0xFF14B8A6),
  Color(0xFF9B7BFF),
  Color(0xFFFF8A3D),
  Color(0xFFEF4444),
  Color(0xFF2FBF71),
  Color(0xFFE879F9),
  Color(0xFFF4A261),
];

class FocusTabPage extends StatefulWidget {
  const FocusTabPage({
    this.authRepository,
    this.focusRepository,
    this.learningTaskRepository,
    this.tabIndex,
    this.refreshListenable,
    this.activeTabListenable,
    this.selectedTaskListenable,
    this.initialTaskId,
    this.onDataChanged,
    super.key,
  });

  final AuthRepository? authRepository;
  final FocusRepository? focusRepository;
  final LearningTaskRepository? learningTaskRepository;
  final int? tabIndex;
  final ValueListenable<int>? refreshListenable;
  final ValueListenable<int>? activeTabListenable;
  final ValueListenable<int?>? selectedTaskListenable;
  final int? initialTaskId;
  final VoidCallback? onDataChanged;

  @override
  State<FocusTabPage> createState() => _FocusTabPageState();
}

class _FocusTabPageState extends State<FocusTabPage>
    with WidgetsBindingObserver {
  late final AuthRepository _authRepository;
  late final FocusRepository _focusRepository;
  late final LearningTaskRepository _learningTasks;
  UserProfile? _user;
  FocusStats? _stats;
  List<PomodoroTask> _tasks = [];
  List<PomodoroRecord> _records = [];
  PomodoroRecord? _activeRecord;
  int? _selectedTaskId;
  int? _requestedTaskId;
  int _secondsElapsed = 0;
  int _period = 0;
  bool _isLoading = true;
  bool _loading = false;
  bool _reloadPending = false;
  bool _busy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _focusRepository = widget.focusRepository ?? FocusRepository();
    _learningTasks = widget.learningTaskRepository ?? LearningTaskRepository();
    WidgetsBinding.instance.addObserver(this);
    widget.refreshListenable?.addListener(_handleExternalRefresh);
    widget.activeTabListenable?.addListener(_handleExternalRefresh);
    widget.selectedTaskListenable?.addListener(_handleSelectedTask);
    LearningEvents.changed.addListener(_handleExternalRefresh);
    _requestedTaskId =
        widget.initialTaskId ?? widget.selectedTaskListenable?.value;
    _loadData();
  }

  @override
  void didUpdateWidget(covariant FocusTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTaskId != widget.initialTaskId &&
        widget.initialTaskId != null) {
      _requestedTaskId = widget.initialTaskId;
      _handleExternalRefresh();
    }
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_handleExternalRefresh);
      widget.refreshListenable?.addListener(_handleExternalRefresh);
    }
    if (oldWidget.activeTabListenable != widget.activeTabListenable) {
      oldWidget.activeTabListenable?.removeListener(_handleExternalRefresh);
      widget.activeTabListenable?.addListener(_handleExternalRefresh);
    }
    if (oldWidget.selectedTaskListenable != widget.selectedTaskListenable) {
      oldWidget.selectedTaskListenable?.removeListener(_handleSelectedTask);
      widget.selectedTaskListenable?.addListener(_handleSelectedTask);
      _handleSelectedTask();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.refreshListenable?.removeListener(_handleExternalRefresh);
    widget.activeTabListenable?.removeListener(_handleExternalRefresh);
    widget.selectedTaskListenable?.removeListener(_handleSelectedTask);
    LearningEvents.changed.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _handleExternalRefresh();
  }

  bool get _isVisible =>
      widget.tabIndex == null ||
      widget.activeTabListenable == null ||
      widget.activeTabListenable!.value == widget.tabIndex;

  void _handleExternalRefresh() {
    if (!_isVisible || !mounted) return;
    if (_busy || _loading) {
      _reloadPending = true;
      return;
    }
    _loadData();
  }

  void _handleSelectedTask() {
    _requestedTaskId = widget.selectedTaskListenable?.value;
    _handleExternalRefresh();
  }

  Future<void> _loadData() async {
    if (_loading || _busy) {
      _reloadPending = true;
      return;
    }
    _loading = true;
    try {
      await _authRepository.ensureInitialized();
      await _focusRepository.ensureInitialized();
      final user = await _authRepository.getCurrentUserProfile();
      if (user == null) throw StateError('请先登录后使用专注');
      await _learningTasks.reconcile(user.id);
      final tasks = await _focusRepository.fetchTasks(user.id);
      final stats = await _focusRepository.fetchStats(user.id);
      final active = await _focusRepository.restoreActiveRecord(user.id);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final week = today.subtract(Duration(days: now.weekday - 1));
      final month = DateTime(now.year, now.month);
      final records = await _focusRepository.fetchRecords(
        userId: user.id,
        fromDate: week.isBefore(month) ? week : month,
        toDate: now,
      );
      if (!mounted) return;
      setState(() {
        _user = user;
        _tasks = tasks;
        _stats = stats;
        _records = records.where((r) => r.completed).toList();
        _activeRecord = active;
        _error = null;
        _isLoading = false;
        if (active != null) {
          _selectedTaskId = active.taskId;
        } else if (_requestedTaskId != null) {
          if (tasks.any((t) => t.id == _requestedTaskId)) {
            _selectedTaskId = _requestedTaskId;
          } else {
            _error = '所选任务不可用，请重新选择';
          }
          _requestedTaskId = null;
        } else if (!tasks.any((t) => t.id == _selectedTaskId)) {
          _selectedTaskId = null;
        }
      });
      _syncClock();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载失败：$e';
        });
      }
    } finally {
      _loading = false;
      if (_reloadPending && mounted) {
        _reloadPending = false;
        _handleExternalRefresh();
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _save(Future<void> Function() action) async {
    if (_busy || _loading || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      widget.onDataChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
      _showMessage('保存失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Repository events emitted by this save are coalesced into one reload.
        _reloadPending = false;
        await _loadData();
      }
    }
  }

  void _syncClock() {
    _timer?.cancel();
    void tick() {
      if (!mounted) return;
      final record = _activeRecord;
      setState(
        () => _secondsElapsed = record?.elapsedSecondsAt(DateTime.now()) ?? 0,
      );
      if (record != null &&
          record.isRunning &&
          record.targetSeconds > 0 &&
          _secondsElapsed >= record.targetSeconds &&
          !_busy &&
          !_loading) {
        _finishTimer();
      }
    }

    tick();
    if (_activeRecord?.isRunning == true) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
    // A restored timer may already have reached its target.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final record = _activeRecord;
      if (mounted &&
          !_busy &&
          !_loading &&
          record?.isRunning == true &&
          record!.targetSeconds > 0 &&
          record.elapsedSecondsAt(DateTime.now()) >= record.targetSeconds) {
        _finishTimer();
      }
    });
  }

  Future<void> _startTimer() async {
    if (_user == null || _activeRecord != null) return;
    if (_selectedTaskId == null) {
      await _chooseTask();
      return;
    }
    await _save(() async {
      _activeRecord = await _focusRepository.startRecord(
        userId: _user!.id,
        taskId: _selectedTaskId!,
        pomodoroMode: '正向',
      );
    });
  }

  Future<void> _pauseOrResume() async {
    final record = _activeRecord;
    if (record == null) return;
    await _save(() async {
      _activeRecord = record.isRunning
          ? await _focusRepository.pauseRecord(record.id)
          : await _focusRepository.resumeRecord(record.id);
    });
  }

  Future<void> _finishTimer() async {
    final record = _activeRecord;
    if (record == null) return;
    await _save(() async {
      await _focusRepository.completeRecord(record.id, _secondsElapsed);
      _activeRecord = null;
    });
  }

  Future<void> _chooseTask() async {
    if (_busy || _activeRecord != null) return;
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .6,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  '选择专注任务',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: _tasks.isEmpty
                    ? const Center(child: Text('请先添加一个待办任务'))
                    : ListView(
                        children: _tasks
                            .map(
                              (t) => ListTile(
                                title: Text(t.title),
                                subtitle: Text(
                                  '预估 ${t.estimatedPomodoros} 个番茄',
                                ),
                                trailing: t.id == _selectedTaskId
                                    ? const Icon(Icons.check, color: _focusBlue)
                                    : null,
                                onTap: () => Navigator.pop(ctx, t.id),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (id != null && mounted && _activeRecord == null) {
      setState(() => _selectedTaskId = id);
    }
  }

  Future<void> _editTask([PomodoroTask? task]) async {
    if (_busy || _user == null) return;
    final title = TextEditingController(text: task?.title ?? '');
    final estimate = TextEditingController(
      text: '${task?.estimatedPomodoros ?? 1}',
    );
    final form = GlobalKey<FormState>();
    final route = DialogRoute<(String, int)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task == null ? '新建待办' : '编辑待办'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '任务名称'),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? '请输入任务名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: estimate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '预估番茄数（1–99）'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 1 || n > 99 ? '请输入 1–99' : null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, (
                  title.text.trim(),
                  int.parse(estimate.text),
                ));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route);
    unawaited(
      route.completed.then((_) {
        title.dispose();
        estimate.dispose();
      }),
    );
    if (result == null || !mounted) return;
    await _save(() async {
      if (task == null) {
        final created = await _focusRepository.createTask(
          userId: _user!.id,
          title: result.$1,
          estimatedPomodoros: result.$2,
        );
        _selectedTaskId ??= created.id;
      } else {
        await _focusRepository.updateTask(
          task.copyWith(title: result.$1, estimatedPomodoros: result.$2),
        );
      }
    });
  }

  Future<void> _deleteTask(PomodoroTask task) async {
    if (_activeRecord?.taskId == task.id) {
      _showMessage('请先结束该任务的专注');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除「${task.title}」吗？专注记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _save(
        () => _focusRepository.deleteTask(task.id, userId: _user!.id),
      );
    }
  }

  Future<void> _doCheckin() async {
    if (_user == null || _stats?.isCheckedInToday == true) return;
    await _save(() async {
      await _focusRepository.checkInToday(_user!.id);
    });
  }

  Future<void> _showCheckinCalendar() async {
    if (_user == null || _busy) return;
    try {
      final now = DateTime.now();
      final records = await _focusRepository.fetchCheckins(
        userId: _user!.id,
        year: now.year,
        month: now.month,
      );
      final points = await _focusRepository.getTotalPoints(_user!.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _CheckinCalendarPage(
            records: records,
            currentMonth: now,
            totalPoints: points,
            focusRepository: _focusRepository,
            userId: _user!.id,
          ),
        ),
      );
      if (mounted) await _loadData();
    } catch (e) {
      _showMessage('日历加载失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _focusBlue));
    }
    return Material(
      color: _focusBackground,
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '专注',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF17233B),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '把时间留给重要的事',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8A94A6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '打卡日历',
                  onPressed: _busy ? null : _showCheckinCalendar,
                  icon: const Icon(
                    Icons.calendar_month_outlined,
                    color: _focusBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _loadData,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            _buildCheckin(),
            const SizedBox(height: 16),
            _buildStats(),
            const SizedBox(height: 20),
            _buildTimer(),
            const SizedBox(height: 20),
            _buildTasks(),
            const SizedBox(height: 20),
            _buildRecords(),
          ],
        ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFEDF0F6)),
    ),
    child: child,
  );

  Widget _buildCheckin() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _focusBlue,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.local_fire_department_rounded,
          color: Colors.white,
          size: 30,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '专注打卡',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '已连续打卡 ${_stats?.currentStreak ?? 0} 天',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _focusBlue,
          ),
          onPressed: _busy || _stats?.isCheckedInToday == true
              ? null
              : _doCheckin,
          child: Text(
            _stats?.isCheckedInToday == true ? '已打卡' : '打卡',
            style: const TextStyle(
              color: _focusBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildStats() {
    final values = [
      _formatSeconds(_stats?.todaySeconds ?? 0),
      '${_stats?.todayPomodoros ?? 0}个',
      '${_stats?.totalPoints ?? 0}',
    ];
    const labels = ['今日专注', '完成番茄', '累计积分'];
    return Row(
      children: List.generate(
        3,
        (i) => Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    values[i],
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: _focusBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A94A6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimer() {
    final record = _activeRecord;
    final task = _tasks.where((t) => t.id == _selectedTaskId).firstOrNull;
    return _card(
      Column(
        children: [
          const Text(
            '专注时间',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 22),
          Text(
            record == null
                ? '准备好开始了吗'
                : record.isRunning
                ? '正在专注'
                : '已暂停',
            style: const TextStyle(color: Color(0xFF8A94A6), fontSize: 13),
          ),
          const SizedBox(height: 10),
          FittedBox(
            child: Text(
              _formatTimer(_secondsElapsed),
              style: const TextStyle(
                fontSize: 60,
                fontWeight: FontWeight.w700,
                color: Color(0xFF17233B),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            task?.title ?? record?.taskTitle ?? '选择一个学习任务',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A94A6)),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _busy || record != null ? null : _chooseTask,
            icon: const Icon(Icons.assignment_outlined, size: 18),
            label: const Text('选择任务'),
            style: TextButton.styleFrom(foregroundColor: _focusBlue),
          ),
          const SizedBox(height: 10),
          if (record == null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _focusBlue,
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: _busy || _user == null ? null : _startTimer,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开始专注'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _focusBlue),
                    onPressed: _busy ? null : _pauseOrResume,
                    icon: Icon(
                      record.isRunning
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(record.isRunning ? '暂停' : '继续'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _finishTimer,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('结束'),
                  ),
                ),
              ],
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(color: _focusBlue),
            ),
        ],
      ),
    );
  }

  Widget _buildTasks() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '待办任务',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: '新建任务',
              onPressed: _busy ? null : () => _editTask(),
              icon: const Icon(Icons.add, color: _focusBlue),
            ),
          ],
        ),
        if (_tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              '还没有待办，添加一个小目标吧',
              style: TextStyle(color: Color(0xFF8A94A6)),
            ),
          ),
        ..._tasks.map(
          (task) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                IconButton(
                  tooltip: '选择此任务',
                  onPressed: _busy || _activeRecord != null
                      ? null
                      : () => setState(() => _selectedTaskId = task.id),
                  icon: Icon(
                    _selectedTaskId == task.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: _focusBlue,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '预估 ${task.estimatedPomodoros} 个番茄 · 已专注 ${_formatSeconds(task.focusedSeconds)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8A94A6),
                        ),
                      ),
                      if ((task.documentTitle ?? '').isNotEmpty)
                        Text(
                          task.documentTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8A94A6),
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !_busy,
                  tooltip: '管理任务',
                  onSelected: (value) =>
                      value == 'edit' ? _editTask(task) : _deleteTask(task),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildRecords() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (_period) {
      1 => today.subtract(Duration(days: now.weekday - 1)),
      2 => DateTime(now.year, now.month),
      _ => today,
    };
    final periodSeconds = switch (_period) {
      1 => _stats?.weekSeconds ?? 0,
      2 => _stats?.monthSeconds ?? 0,
      _ => _stats?.todaySeconds ?? 0,
    };
    // Aggregate by task so the pie shows how the period's time was distributed.
    final secondsByTask = <int, int>{};
    final titleByTask = <int, String>{};
    for (final r in _records) {
      final seconds = r.secondsInRange(from, now);
      if (seconds <= 0) continue;
      secondsByTask[r.taskId] = (secondsByTask[r.taskId] ?? 0) + seconds;
      titleByTask[r.taskId] = r.taskTitle;
    }
    final slices =
        secondsByTask.entries
            .map((e) => _PieSlice(titleByTask[e.key] ?? '', e.value))
            .toList()
          ..sort((a, b) => b.seconds.compareTo(a.seconds));
    final sliceTotal = slices.fold<int>(0, (sum, s) => sum + s.seconds);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '专注记录',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Center(child: Text(const ['今日', '本周', '本月'][i])),
                    selected: _period == i,
                    showCheckmark: false,
                    selectedColor: const Color(0xFFEAF0FF),
                    labelStyle: TextStyle(
                      color: _period == i
                          ? _focusBlue
                          : const Color(0xFF8A94A6),
                    ),
                    onSelected: (_) => setState(() => _period = i),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '共 ${_formatSeconds(periodSeconds)}',
            style: const TextStyle(color: _focusBlue),
          ),
          if (slices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '暂无专注记录',
                  style: TextStyle(color: Color(0xFF8A94A6)),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 16),
            Center(child: _FocusPieChart(slices: slices)),
            const SizedBox(height: 18),
            ...slices.indexed.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _pieColors[entry.$1 % _pieColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.$2.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatSeconds(entry.$2.seconds),
                      style: const TextStyle(
                        color: _focusBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text(
                        '${(entry.$2.seconds / sliceTotal * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A94A6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimer(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  String _formatSeconds(int seconds) {
    if (seconds >= 3600) return '${seconds ~/ 3600}h${seconds % 3600 ~/ 60}m';
    if (seconds < 60 && seconds > 0) return '$seconds秒';
    return '${seconds ~/ 60}分钟';
  }
}

// ========== Focus Records Pie Chart ==========

class _PieSlice {
  const _PieSlice(this.title, this.seconds);
  final String title;
  final int seconds;
}

class _FocusPieChart extends StatelessWidget {
  const _FocusPieChart({required this.slices});

  final List<_PieSlice> slices;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 168,
    height: 168,
    child: CustomPaint(painter: _FocusPiePainter(slices)),
  );
}

class _FocusPiePainter extends CustomPainter {
  _FocusPiePainter(this.slices);

  final List<_PieSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, s) => sum + s.seconds);
    if (total <= 0) return;
    final circle = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.shortestSide / 2,
    );
    final separator = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    // Start at 12 o'clock so the largest slice reads clockwise from the top.
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].seconds / total * 2 * math.pi;
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = _pieColors[i % _pieColors.length];
      canvas.drawArc(circle, start, sweep, true, fill);
      canvas.drawArc(circle, start, sweep, true, separator);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _FocusPiePainter oldDelegate) =>
      oldDelegate.slices != slices;
}

// ========== Checkin Calendar Page ==========

class _CheckinCalendarPage extends StatelessWidget {
  const _CheckinCalendarPage({
    required this.records,
    required this.currentMonth,
    required this.totalPoints,
    required this.focusRepository,
    required this.userId,
  });

  final List<CheckinRecord> records;
  final DateTime currentMonth;
  final int totalPoints;
  final FocusRepository focusRepository;
  final int userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('打卡日历')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _CalendarMonthView(
          records: records,
          currentMonth: currentMonth,
          totalPoints: totalPoints,
          focusRepository: focusRepository,
          userId: userId,
        ),
      ),
    );
  }
}

class _CalendarMonthView extends StatefulWidget {
  const _CalendarMonthView({
    required this.records,
    required this.currentMonth,
    required this.totalPoints,
    required this.focusRepository,
    required this.userId,
  });

  final List<CheckinRecord> records;
  final DateTime currentMonth;
  final int totalPoints;
  final FocusRepository focusRepository;
  final int userId;

  @override
  State<_CalendarMonthView> createState() => _CalendarMonthViewState();
}

class _CalendarMonthViewState extends State<_CalendarMonthView> {
  late DateTime _currentMonth;
  late List<CheckinRecord> _records;
  late int _totalPoints;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentMonth = widget.currentMonth;
    _records = widget.records;
    _totalPoints = widget.totalPoints;
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
    _loadMonth();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() => _isLoading = true);
    _records = await widget.focusRepository.fetchCheckins(
      userId: widget.userId,
      year: _currentMonth.year,
      month: _currentMonth.month,
    );
    _totalPoints = await widget.focusRepository.getTotalPoints(widget.userId);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _makeupCheckin(DateTime date) async {
    final success = await widget.focusRepository.makeupCheckin(
      widget.userId,
      date,
    );
    if (!mounted) return;
    if (success) {
      await _loadMonth();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已补签 ${date.month}/${date.day}！消耗 ${FocusPoints.makeupCost} 积分',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('补签失败：积分不足（需要 ${FocusPoints.makeupCost} 分）或日期超出范围'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordMap = {for (final r in _records) r.dateKey: r};
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final firstWeekday = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    ).weekday;
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Points header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF5F3FF), Color(0xFFFDF2F8)],
              ),
              borderRadius: BorderRadius.circular(AppRadii.cardSmall),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.stars_rounded,
                  color: AppColors.secondaryPurple,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前积分', style: AppTextStyles.caption(context)),
                    Text(
                      '$_totalPoints ⭐',
                      style: AppTextStyles.h2(
                        context,
                      ).copyWith(color: AppColors.secondaryPurple),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '补签消耗 ${FocusPoints.makeupCost} 分',
                  style: AppTextStyles.caption(
                    context,
                  ).copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Month nav
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _previousMonth,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                '${_currentMonth.year}年${_currentMonth.month}月',
                style: AppTextStyles.h3(context),
              ),
              IconButton(
                onPressed: _nextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Calendar grid with LayoutBuilder for overflow-safe sizing
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = (constraints.maxWidth) / 7;

              // Weekday headers
              return Column(
                children: [
                  Row(
                    children: weekdays.map((w) {
                      return SizedBox(
                        width: cellWidth,
                        child: Center(
                          child: Text(
                            w,
                            style: AppTextStyles.caption(
                              context,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),

                  // Calendar grid
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    Builder(
                      builder: (context) {
                        final cells = <Widget>[];
                        for (int i = 1; i < firstWeekday; i++) {
                          cells.add(const SizedBox());
                        }
                        for (int day = 1; day <= daysInMonth; day++) {
                          final date = DateTime(
                            _currentMonth.year,
                            _currentMonth.month,
                            day,
                          );
                          final key =
                              '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                          final record = recordMap[key];
                          final isToday = key == todayKey;
                          final isPast = date.isBefore(
                            DateTime(now.year, now.month, now.day),
                          );
                          final canMakeup =
                              isPast &&
                              record == null &&
                              date.isAfter(
                                now.subtract(const Duration(days: 30)),
                              );

                          cells.add(
                            GestureDetector(
                              onLongPress: canMakeup
                                  ? () => _makeupCheckin(date)
                                  : null,
                              child: Container(
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: record != null
                                      ? (record.isMakeup
                                            ? AppColors.secondaryPurple
                                                  .withValues(alpha: 0.2)
                                            : AppColors.primarySoft)
                                      : (isToday
                                            ? AppColors.primaryLight
                                            : AppColors.surfaceAlt),
                                  borderRadius: BorderRadius.circular(12),
                                  border: isToday
                                      ? Border.all(
                                          color: AppColors.primary,
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$day',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isToday
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: record != null
                                              ? AppColors.primaryDark
                                              : (isToday
                                                    ? AppColors.primary
                                                    : AppColors.textPrimary),
                                        ),
                                      ),
                                      if (record != null)
                                        Text(
                                          record.isMakeup ? '补' : '✓',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: record.isMakeup
                                                ? AppColors.secondaryPurple
                                                : AppColors.success,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      if (canMakeup && record == null)
                                        const Text(
                                          '·',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: [
                            for (
                              int row = 0;
                              row < (cells.length / 7).ceil();
                              row++
                            )
                              Row(
                                children: List.generate(7, (col) {
                                  final idx = row * 7 + col;
                                  return Expanded(
                                    child: idx < cells.length
                                        ? cells[idx]
                                        : const SizedBox(),
                                  );
                                }),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          Text(
            '长按灰色日期可以补签（消耗 ${FocusPoints.makeupCost} 积分，仅限过去30天）',
            style: AppTextStyles.caption(context),
          ),
        ],
      ),
    );
  }
}
