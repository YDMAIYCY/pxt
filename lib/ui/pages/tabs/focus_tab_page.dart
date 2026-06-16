import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../database/auth_repository.dart';
import '../../../database/models/user_profile.dart';
import '../../../focus/models/pomodoro_task.dart';
import '../../../focus/models/checkin_record.dart';
import '../../../focus/repository/focus_repository.dart';
import '../../theme/app_theme.dart';

const List<Color> _pieColors = [
  Color(0xFF14B8A6),
  Color(0xFF4FA3FF),
  Color(0xFF9B7BFF),
  Color(0xFFFF8A3D),
  Color(0xFFF4A261),
  Color(0xFFEF4444),
  Color(0xFF2FBF71),
  Color(0xFFE879F9),
];

class FocusTabPage extends StatefulWidget {
  const FocusTabPage({
    this.authRepository,
    this.focusRepository,
    this.tabIndex,
    this.refreshListenable,
    this.activeTabListenable,
    this.onDataChanged,
    super.key,
  });

  final AuthRepository? authRepository;
  final FocusRepository? focusRepository;
  final int? tabIndex;
  final ValueListenable<int>? refreshListenable;
  final ValueListenable<int>? activeTabListenable;
  final VoidCallback? onDataChanged;

  @override
  State<FocusTabPage> createState() => _FocusTabPageState();
}

class _FocusTabPageState extends State<FocusTabPage> with TickerProviderStateMixin {
  late final AuthRepository _authRepository;
  late final FocusRepository _focusRepository;

  UserProfile? _user;
  FocusStats? _stats;
  List<PomodoroTask> _tasks = [];
  List<TaskTimeStat> _todayStats = [];
  List<TaskTimeStat> _weekStats = [];
  List<TaskTimeStat> _monthStats = [];
  bool _isLoading = true;
  bool _reloadScheduled = false;

  // Timer state
  bool _isTimerRunning = false;
  int _secondsElapsed = 0;
  int? _activeTaskId;
  int? _activeRecordId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _focusRepository = widget.focusRepository ?? FocusRepository();
    widget.refreshListenable?.addListener(_handleExternalRefresh);
    widget.activeTabListenable?.addListener(_handleExternalRefresh);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant FocusTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_handleExternalRefresh);
      widget.refreshListenable?.addListener(_handleExternalRefresh);
    }
    if (oldWidget.activeTabListenable != widget.activeTabListenable) {
      oldWidget.activeTabListenable?.removeListener(_handleExternalRefresh);
      widget.activeTabListenable?.addListener(_handleExternalRefresh);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      _loadData();
    });
  }

  Future<void> _loadData() async {
    try {
      await _authRepository.ensureInitialized();
      await _focusRepository.ensureInitialized();
      final user = await _authRepository.getCurrentUserProfile();
      if (user == null) return;

      final stats = await _focusRepository.fetchStats(user.id);
      final tasks = await _focusRepository.fetchTasks(user.id);

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
      final monthStart = DateTime(now.year, now.month, 1);

      final todayStats = await _focusRepository.fetchTaskTimeStats(
        userId: user.id,
        fromDate: todayStart,
        toDate: now,
      );
      final weekStats = await _focusRepository.fetchTaskTimeStats(
        userId: user.id,
        fromDate: weekStart,
        toDate: now,
      );
      final monthStats = await _focusRepository.fetchTaskTimeStats(
        userId: user.id,
        fromDate: monthStart,
        toDate: now,
      );

      if (!mounted) return;
      setState(() {
        _user = user;
        _stats = stats;
        _tasks = tasks;
        _todayStats = todayStats;
        _weekStats = weekStats;
        _monthStats = monthStats;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ========== Timer Logic ==========

  void _startTimer(int taskId) {
    setState(() {
      _isTimerRunning = true;
      _activeTaskId = taskId;
      _secondsElapsed = 0;
    });
    _startActiveTimer();
    _createTimerRecord(taskId);
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isTimerRunning = false);
  }

  void _resumeTimer() {
    setState(() => _isTimerRunning = true);
    _startActiveTimer();
  }

  void _stopTimer() {
    _timer?.cancel();
    final elapsed = _secondsElapsed;
    if (_activeRecordId != null) {
      _focusRepository.completeRecord(_activeRecordId!, elapsed);
    }
    _updateCheckinAfterFocus(elapsed);
    setState(() {
      _isTimerRunning = false;
      _activeTaskId = null;
      _activeRecordId = null;
      _secondsElapsed = 0;
    });
  }

  void _startActiveTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  Future<void> _updateCheckinAfterFocus(int elapsedSeconds) async {
    if (_user == null || elapsedSeconds <= 0) return;
    await _focusRepository.checkInToday(_user!.id);
    final stats = await _focusRepository.fetchStats(_user!.id);
    final seconds = stats.todaySeconds + elapsedSeconds;
    final count = stats.todayPomodoros + 1;
    await _focusRepository.updateCheckinStudyTime(_user!.id, seconds, count);
    if (mounted) {
      final newStats = await _focusRepository.fetchStats(_user!.id);
      final newToday = await _focusRepository.fetchTaskTimeStats(
        userId: _user!.id,
        fromDate: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
        toDate: DateTime.now(),
      );
      setState(() {
        _stats = newStats;
        _todayStats = newToday;
      });
      widget.onDataChanged?.call();
    }
  }

  Future<void> _createTimerRecord(int taskId) async {
    if (_user == null) return;
    final record = await _focusRepository.startRecord(
      userId: _user!.id,
      taskId: taskId,
      pomodoroMode: '正向',
    );
    if (mounted) setState(() => _activeRecordId = record.id);
  }

  // ========== Task CRUD ==========

  Future<void> _addTask() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建待办'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入任务名称'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    if (_user == null) return;
    await _focusRepository.createTask(userId: _user!.id, title: title);
    final tasks = await _focusRepository.fetchTasks(_user!.id);
    if (mounted) setState(() => _tasks = tasks);
  }

  Future<void> _deleteTask(PomodoroTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除「${task.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _focusRepository.deleteTask(task.id);
      final tasks = await _focusRepository.fetchTasks(_user!.id);
      if (mounted) setState(() => _tasks = tasks);
    }
  }

  // ========== Checkin ==========

  Future<void> _doCheckin() async {
    if (_user == null) return;
    if (_stats?.isCheckedInToday == true) {
      _showMessage('今日已打卡！');
      return;
    }
    final record = await _focusRepository.checkInToday(_user!.id);
    if (record != null && mounted) {
      final stats = await _focusRepository.fetchStats(_user!.id);
      setState(() => _stats = stats);
      _showMessage('打卡成功！');
      widget.onDataChanged?.call();
    }
  }

  Future<void> _showCheckinCalendar() async {
    if (_user == null) return;
    final now = DateTime.now();
    final records = await _focusRepository.fetchCheckins(
      userId: _user!.id,
      year: now.year,
      month: now.month,
    );
    final totalPoints = await _focusRepository.getTotalPoints(_user!.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CheckinCalendarPage(
          records: records,
          currentMonth: now,
          totalPoints: totalPoints,
          focusRepository: _focusRepository,
          userId: _user!.id,
        ),
      ),
    );
    if (mounted) {
      final stats = await _focusRepository.fetchStats(_user!.id);
      setState(() => _stats = stats);
    }
  }

  // ========== Build ==========

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: () async => _loadData(),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCheckinBanner(),
                  const SizedBox(height: 14),
                  _buildTimerCard(),
                  const SizedBox(height: 14),
                  _buildTaskList(),
                  const SizedBox(height: 14),
                  _buildStatsSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== Check-in Banner ==========

  Widget _buildCheckinBanner() {
    final stats = _stats;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_fire_department_rounded, color: AppColors.accentOrange, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('专注打卡', style: AppTextStyles.h2(context)),
                  ],
                ),
              ),
              if (stats?.isCheckedInToday == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('已打卡', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12)),
                )
              else
                _SmallChip(
                  label: '打卡',
                  icon: Icons.check_rounded,
                  color: AppColors.primary,
                  onTap: _doCheckin,
                ),
              const SizedBox(width: 6),
              _SmallChip(
                label: '日历',
                icon: Icons.calendar_month_rounded,
                color: AppColors.secondaryBlue,
                onTap: _showCheckinCalendar,
              ),
            ],
          ),
          if (stats != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _MiniStatBadge(icon: Icons.timer_rounded, label: '今日', value: _formatSeconds(stats.todaySeconds)),
                const SizedBox(width: 10),
                _MiniStatBadge(icon: Icons.track_changes_rounded, label: '番茄', value: '${stats.todayPomodoros}个'),
                const SizedBox(width: 10),
                _MiniStatBadge(icon: Icons.stars_rounded, label: '积分', value: '${stats.totalPoints}'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ========== Timer Card ==========

  Widget _buildTimerCard() {
    final isRunning = _isTimerRunning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Column(
        children: [
          // Timer display
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primarySoft.withValues(alpha: 0.3),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_activeTaskId != null)
                      Text(
                        _tasks.where((t) => t.id == _activeTaskId).map((t) => t.title).firstOrNull ?? '专注',
                        style: AppTextStyles.caption(context).copyWith(fontWeight: FontWeight.w600),
                      )
                    else
                      Text(
                        '专注',
                        style: AppTextStyles.caption(context).copyWith(fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimer(_secondsElapsed),
                      style: AppTextStyles.display(context).copyWith(fontSize: 42, fontWeight: FontWeight.w800),
                    ),
                    if (isRunning)
                      Text(
                        '计时中',
                        style: AppTextStyles.caption(context).copyWith(color: AppColors.primary),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Timer controls
          if (_activeTaskId != null || isRunning)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isRunning) ...[
                  _TimerButton(
                    icon: Icons.pause_rounded,
                    label: '暂停',
                    onTap: _pauseTimer,
                  ),
                  const SizedBox(width: 16),
                  _TimerButton(
                    icon: Icons.stop_rounded,
                    label: '结束',
                    color: AppColors.error,
                    onTap: _stopTimer,
                  ),
                ] else if (_activeTaskId != null) ...[
                  _TimerButton(
                    icon: Icons.play_arrow_rounded,
                    label: '继续',
                    onTap: _resumeTimer,
                  ),
                  const SizedBox(width: 16),
                  _TimerButton(
                    icon: Icons.stop_rounded,
                    label: '结束',
                    color: AppColors.error,
                    onTap: _stopTimer,
                  ),
                ],
              ],
            )
          else
            Text(
              '点击下方任务开始计时',
              style: AppTextStyles.caption(context),
            ),
        ],
      ),
    );
  }

  // ========== Task List ==========

  Widget _buildTaskList() {
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
          Row(
            children: [
              Text('待办列表', style: AppTextStyles.h3(context)),
              const Spacer(),
              IconButton(
                onPressed: _addTask,
                icon: const Icon(Icons.add_rounded, color: AppColors.primary),
                tooltip: '新建任务',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_tasks.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.input),
              ),
              child: const Text('还没有待办项，点击右上角 + 创建', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ..._tasks.map((task) => _TaskTile(
              task: task,
              isActive: _activeTaskId == task.id && _isTimerRunning,
              onStart: () => _startTimer(task.id),
              onDelete: () => _deleteTask(task),
              timerRunning: _isTimerRunning,
            )),
        ],
      ),
    );
  }

  // ========== Stats Section ==========

  Widget _buildStatsSection() {
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
          Text('时间统计', style: AppTextStyles.h3(context)),
          const SizedBox(height: 12),
          DefaultTabController(
            length: 3,
            child: Column(
              children: [
                TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  tabs: const [
                    Tab(text: '今日'),
                    Tab(text: '本周'),
                    Tab(text: '本月'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: TabBarView(
                    children: [
                      _PieChartView(data: _todayStats, emptyText: '今日暂无专注记录'),
                      _PieChartView(data: _weekStats, emptyText: '本周暂无专注记录'),
                      _PieChartView(data: _monthStats, emptyText: '本月暂无专注记录'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimer(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatSeconds(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h${m}m';
    return '$m分钟';
  }
}

// ========== Mini Widgets ==========

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, required this.icon, required this.color, this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStatBadge extends StatelessWidget {
  const _MiniStatBadge({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text('$label ', style: AppTextStyles.caption(context)),
          Text(value, style: AppTextStyles.caption(context).copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _TimerButton extends StatelessWidget {
  const _TimerButton({required this.icon, required this.label, this.color = AppColors.primary, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.isActive, required this.onStart, required this.onDelete, required this.timerRunning});
  final PomodoroTask task;
  final bool isActive;
  final bool timerRunning;
  final VoidCallback onStart;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: timerRunning ? null : onStart,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: isActive ? AppColors.primarySoft : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isActive ? AppColors.primary : AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isActive ? Icons.timer_rounded : Icons.play_arrow_rounded,
                    color: isActive ? Colors.white : AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('预估 ${task.estimatedPomodoros} 个番茄', style: AppTextStyles.caption(context)),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('进行中', style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700, fontSize: 11)),
                  ),
                if (!timerRunning)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: AppColors.textTertiary,
                    tooltip: '删除任务',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========== Pie Chart ==========

class _PieChartView extends StatelessWidget {
  const _PieChartView({required this.data, required this.emptyText});
  final List<TaskTimeStat> data;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final total = data.fold<int>(0, (sum, item) => sum + item.totalSeconds);
    if (total == 0 || data.isEmpty) {
      return Center(
        child: Text(emptyText, style: AppTextStyles.bodySmall(context)),
      );
    }

    return Row(
      children: [
        // Chart
        SizedBox(
          width: 150,
          height: 150,
          child: CustomPaint(
            painter: _PieChartPainter(data: data, totalSeconds: total, colors: _pieColors),
            size: const Size(150, 150),
          ),
        ),
        const SizedBox(width: 20),
        // Legend
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.take(6).toList().asMap().entries.map((entry) {
              final color = _pieColors[entry.key % _pieColors.length];
              final item = entry.value;
              final pct = total > 0 ? (item.totalSeconds / total * 100).toStringAsFixed(0) : '0';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.taskTitle,
                        style: AppTextStyles.caption(context).copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: AppTextStyles.caption(context).copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter({required this.data, required this.totalSeconds, required this.colors});
  final List<TaskTimeStat> data;
  final int totalSeconds;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - 8;

    double startAngle = -math.pi / 2;
    for (int i = 0; i < data.length; i++) {
      final sweepAngle = (data[i].totalSeconds / totalSeconds) * 2 * math.pi;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;

      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }

    // Center hole
    final holePaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.55, holePaint);

    // Total text
    final tp = TextPainter(
      text: TextSpan(
        text: _formatTotal(totalSeconds),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  String _formatTotal(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h${m}m';
    return '$m分';
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter old) => old.data != data || old.totalSeconds != totalSeconds;
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
    final success = await widget.focusRepository.makeupCheckin(widget.userId, date);
    if (!mounted) return;
    if (success) {
      await _loadMonth();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已补签 ${date.month}/${date.day}！消耗 ${FocusPoints.makeupCost} 积分'),
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
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

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
                const Icon(Icons.stars_rounded, color: AppColors.secondaryPurple, size: 24),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前积分', style: AppTextStyles.caption(context)),
                    Text('$_totalPoints ⭐', style: AppTextStyles.h2(context).copyWith(color: AppColors.secondaryPurple)),
                  ],
                ),
                const Spacer(),
                Text('补签消耗 ${FocusPoints.makeupCost} 分', style: AppTextStyles.caption(context).copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Month nav
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: _previousMonth, icon: const Icon(Icons.chevron_left_rounded)),
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
                          child: Text(w, style: AppTextStyles.caption(context).copyWith(fontWeight: FontWeight.w700)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),

                  // Calendar grid
                  if (_isLoading)
                    const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                  else
                    Builder(builder: (context) {
                      final cells = <Widget>[];
                      for (int i = 1; i < firstWeekday; i++) {
                        cells.add(const SizedBox());
                      }
                      for (int day = 1; day <= daysInMonth; day++) {
                        final date = DateTime(_currentMonth.year, _currentMonth.month, day);
                        final key = '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                        final record = recordMap[key];
                        final isToday = key == todayKey;
                        final isPast = date.isBefore(DateTime(now.year, now.month, now.day));
                        final canMakeup = isPast && record == null && date.isAfter(now.subtract(const Duration(days: 30)));

                        cells.add(
                          GestureDetector(
                            onLongPress: canMakeup ? () => _makeupCheckin(date) : null,
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: record != null
                                    ? (record.isMakeup ? AppColors.secondaryPurple.withValues(alpha: 0.2) : AppColors.primarySoft)
                                    : (isToday ? AppColors.primaryLight : AppColors.surfaceAlt),
                                borderRadius: BorderRadius.circular(12),
                                border: isToday ? Border.all(color: AppColors.primary, width: 1.5) : null,
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
                                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                                        color: record != null ? AppColors.primaryDark : (isToday ? AppColors.primary : AppColors.textPrimary),
                                      ),
                                    ),
                                    if (record != null)
                                      Text(
                                        record.isMakeup ? '补' : '✓',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: record.isMakeup ? AppColors.secondaryPurple : AppColors.success,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    if (canMakeup && record == null)
                                      const Text('·', style: TextStyle(fontSize: 9, color: AppColors.textTertiary)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          for (int row = 0; row < (cells.length / 7).ceil(); row++)
                            Row(
                              children: List.generate(7, (col) {
                                final idx = row * 7 + col;
                                return Expanded(child: idx < cells.length ? cells[idx] : const SizedBox());
                              }),
                            ),
                        ],
                      );
                    }),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          Text('长按灰色日期可以补签（消耗 ${FocusPoints.makeupCost} 积分，仅限过去30天）', style: AppTextStyles.caption(context)),
        ],
      ),
    );
  }
}
