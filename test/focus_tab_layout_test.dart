import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/focus/models/pomodoro_task.dart';
import 'package:pxt1/focus/models/pomodoro_record.dart';
import 'package:pxt1/focus/repository/focus_repository.dart';
import 'package:pxt1/learning/learning_task_repository.dart';
import 'package:pxt1/ui/pages/tabs/focus_tab_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

/// Reported device: PLJ110, 1256x2760 at density 560
/// => devicePixelRatio 3.5, logical width 359.
const double _devicePixelRatio = 3.5;
const Size _devicePhysicalSize = Size(1256, 2760);

const _profile = UserProfile(
  id: 1,
  username: 'fixture',
  displayName: 'ydm',
  bio: '',
  gender: 'unknown',
  avatarStyle: 'default',
  backgroundStyle: 'default',
);

/// A realistic active day: 2h15m focused, 12 pomodoros, 1280 points.
const _stats = FocusStats(
  todaySeconds: 8100,
  todayPomodoros: 12,
  weekSeconds: 43200,
  monthSeconds: 129600,
  totalPoints: 1280,
  currentStreak: 6,
  longestStreak: 14,
  isCheckedInToday: true,
);

class _FakeAuthRepository extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<UserProfile?> getCurrentUserProfile() async => _profile;
}

class _FakeFocusRepository extends FocusRepository {
  _FakeFocusRepository({this.tasks = const [], this.taskStats = const []});

  final List<PomodoroTask> tasks;
  final List<TaskTimeStat> taskStats;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<PomodoroRecord?> restoreActiveRecord(int userId) async => null;

  @override
  Future<List<PomodoroRecord>> fetchRecords({required int userId, DateTime? fromDate, DateTime? toDate}) async => [];

  @override
  Future<FocusStats> fetchStats(int userId) async => _stats;

  @override
  Future<List<PomodoroTask>> fetchTasks(int userId) async => tasks;

  @override
  Future<List<TaskTimeStat>> fetchTaskTimeStats({
    required int userId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => taskStats;

  @override
  Future<int> getTotalPoints(int userId) async => _stats.totalPoints;
}

class _FakeLearningTasks extends LearningTaskRepository {
  @override
  Future<void> reconcile(int userId) async {}
}

Future<void> _waitFor(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 200 && target.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(target, findsWidgets);
}

Future<void> _pumpFocusTab(
  WidgetTester tester, {
  required Size physicalSize,
  required double devicePixelRatio,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fontFile = File('C:/Windows/Fonts/msyh.ttc');
  if ((await tester.runAsync(fontFile.exists))!) {
    await tester.runAsync(() async {
      final loader = FontLoader('FocusCJK')
        ..addFont(
          Future.value(ByteData.sublistView(await fontFile.readAsBytes())),
        );
      await loader.load();
    });
  }
  final theme = AppTheme.light.copyWith(
    textTheme: AppTheme.light.textTheme.apply(fontFamily: 'FocusCJK'),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: FocusTabPage(
        authRepository: _FakeAuthRepository(),
        learningTaskRepository: _FakeLearningTasks(),
        focusRepository: _FakeFocusRepository(
          tasks: [
            PomodoroTask(
              id: 1,
              userId: 1,
              title: '高等数学复习',
              estimatedPomodoros: 4,
              createdAt: DateTime(2026, 10, 13),
            ),
          ],
          taskStats: const [
            TaskTimeStat(
              taskId: 1,
              taskTitle: '高等数学复习',
              totalSeconds: 8100,
              colorIndex: 0,
            ),
          ],
        ),
      ),
    ),
  );
  await _waitFor(tester, find.text('专注打卡'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('focus tab header does not overflow on the reported device width', (
    tester,
  ) async {
    // PLJ110: 1256x2760 at density 560 => dpr 3.5, logical width 359.
    await _pumpFocusTab(
      tester,
      physicalSize: _devicePhysicalSize,
      devicePixelRatio: _devicePixelRatio,
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'focus tab header overflowed',
    );
    expect(find.text('专注打卡'), findsOneWidget);
    expect(find.text('2h15m'), findsOneWidget);
    expect(find.text('12个'), findsOneWidget);
    expect(find.text('1280'), findsOneWidget);
  });

  testWidgets('focus tab header does not overflow on a narrow phone', (
    tester,
  ) async {
    await _pumpFocusTab(
      tester,
      physicalSize: const Size(960, 2160),
      devicePixelRatio: 3.0,
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'focus tab header overflowed',
    );
    expect(find.text('专注打卡'), findsOneWidget);
  });
}
