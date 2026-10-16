import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/learning/learning_events.dart';
import 'package:pxt1/learning/learning_task_repository.dart';
import 'package:pxt1/ui/pages/library_practice_page.dart';
import 'package:pxt1/ui/pages/tabs/tasks_tab_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _profile = UserProfile(
  id: 1,
  username: 'fixture',
  displayName: 'fixture',
  bio: '',
  gender: 'unknown',
  avatarStyle: 'default',
  backgroundStyle: 'default',
);

class _Auth extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<UserProfile?> getCurrentUserProfile() async => _profile;
}

class _Tasks extends LearningTaskRepository {
  _Tasks({this.items = const [], this.recommendationsList = const []});
  List<LearningTask> items;
  final List<ReviewRecommendation> recommendationsList;
  Completer<LearningDashboard>? pending;
  bool fail = false;
  int loads = 0;
  int? reviewedConcept;
  final statuses = <String>[];

  @override
  Future<LearningDashboard> dashboard(int userId) async {
    loads++;
    if (fail) throw StateError('offline');
    if (pending != null) return pending!.future;
    return LearningDashboard(
      tasks: items.where((t) => t.active).toList(),
      recommendations: recommendationsList,
      pendingPractice: 12,
      overduePractice: 3,
      wrongQuestions: 5,
      inProgress: 2,
    );
  }

  @override
  Future<List<LearningTask>> tasks(
    int userId, {
    bool includeFinished = false,
  }) async => items;

  @override
  Future<void> setStatus(
    int userId,
    int taskId,
    String status, {
    DateTime? dueAt,
  }) async {
    statuses.add(status);
    items = items
        .map(
          (t) => LearningTask(
            id: t.id,
            userId: t.userId,
            title: t.title,
            kind: t.kind,
            status: t.id == taskId ? status : t.status,
            questionId: t.questionId,
            conceptId: t.conceptId,
            documentId: t.documentId,
          ),
        )
        .toList();
  }

  @override
  Future<void> addConceptReview(
    int userId,
    int conceptId, {
    DateTime? dueAt,
    int importance = 1,
  }) async {
    reviewedConcept = conceptId;
  }
}

const _personal = LearningTask(
  id: 17,
  userId: 1,
  title: '阅读第一章',
  kind: 'personal',
  status: 'pending',
);
const _practice = LearningTask(
  id: 18,
  userId: 1,
  title: '练习矩阵分解',
  kind: 'practice',
  status: 'pending',
  questionId: 91,
  documentId: 12,
  conceptId: 34,
);

Future<void> _pump(
  WidgetTester tester,
  LearningTaskRepository repository, {
  ValueChanged<int>? onStartFocus,
  ValueNotifier<int>? refresh,
  ValueNotifier<int>? active,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: TasksTabPage(
          authRepository: _Auth(),
          learningTaskRepository: repository,
          onStartFocus: onStartFocus,
          refreshListenable: refresh,
          activeTabListenable: active,
          tabIndex: 2,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '320px dashboard shows repository statistics and long cards without overflow',
    (tester) async {
      final repo = _Tasks(
        items: [
          LearningTask(
            id: 1,
            userId: 1,
            title: '复习线性代数第一章的向量空间与线性映射并整理练习中的易错点',
            kind: 'concept_review',
            status: 'in_progress',
            libraryName: '大学课程知识库',
            documentTitle: '线性代数第一章课堂笔记',
            dueAt: DateTime.now().subtract(const Duration(days: 2)),
            focusedSeconds: 1800,
            estimatedPomodoros: 3,
            completedUnits: 1,
            totalUnits: 3,
          ),
        ],
        recommendationsList: const [
          ReviewRecommendation(
            conceptId: 34,
            documentId: 12,
            name: '向量空间与线性映射',
            libraryName: '大学课程知识库',
            reason: '最近的实际答题中错误较多，建议结合课堂笔记复习并再次练习。',
            masteryScore: 35,
            score: .9,
          ),
        ],
      );
      await _pump(tester, repo, scale: 1.3);
      await tester.pumpAndSettle();
      for (final number in ['12', '3', '5', '2']) {
        expect(find.text(number), findsOneWidget);
      }
      expect(find.text('任务中心'), findsOneWidget);
      expect(find.text('concept_review'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('开始复习'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('掌握度 35%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, '加入任务');
      expect(repo.reviewedConcept, 34);
    },
  );

  testWidgets('opening a task never completes it; focus forwards the task id', (
    tester,
  ) async {
    final repo = _Tasks(items: [_personal]);
    int? focused;
    await _pump(tester, repo, onStartFocus: (id) => focused = id);
    await tester.pumpAndSettle();
    await _tap(tester, _personal.title);
    expect(repo.statuses, isEmpty);
    expect(find.text('手动完成'), findsOneWidget);
    await _tap(tester, '专注学习');
    expect(focused, 17);
    expect(repo.statuses, isEmpty);
  });

  testWidgets(
    'practice tasks cannot be manually completed and open the exact question scope',
    (tester) async {
      final repo = _Tasks(items: [_practice]);
      await _pump(tester, repo);
      await tester.pumpAndSettle();
      await _tap(tester, _practice.title);
      expect(find.text('手动完成'), findsNothing);
      await _tap(tester, '直接学习');
      final page = tester.widget<LibraryPracticePage>(
        find.byType(LibraryPracticePage),
      );
      expect(page.documentId, 12);
      expect(page.initialConceptId, 34);
      expect(page.initialQuestionId, 91);
      expect(page.questionIds, [91]);
      expect(repo.statuses, isEmpty);
    },
  );

  testWidgets(
    'pause and resume persist statuses; deleting requires confirmation',
    (tester) async {
      final repo = _Tasks(items: [_personal]);
      await _pump(tester, repo);
      await tester.pumpAndSettle();
      await _tap(tester, _personal.title);
      await _tap(tester, '暂停任务');
      expect(repo.statuses, ['paused']);
      await _tap(tester, _personal.title);
      await _tap(tester, '继续任务');
      expect(repo.statuses.last, 'in_progress');
      await _tap(tester, _personal.title);
      await _tap(tester, '删除任务');
      expect(repo.statuses, hasLength(2));
      await _tap(tester, '保留');
      expect(repo.statuses, hasLength(2));
      await _tap(tester, _personal.title);
      await _tap(tester, '删除任务');
      await _tap(tester, '确认删除');
      expect(repo.statuses.last, 'deleted');
    },
  );

  testWidgets(
    'all tasks includes finished and future tasks; AI header retains legacy list',
    (tester) async {
      final repo = _Tasks(
        items: [
          _personal,
          const LearningTask(
            id: 20,
            userId: 1,
            title: '已完成的阅读',
            kind: 'personal',
            status: 'completed',
          ),
          LearningTask(
            id: 21,
            userId: 1,
            title: '下周预习',
            kind: 'personal',
            status: 'pending',
            dueAt: DateTime.now().add(const Duration(days: 7)),
          ),
        ],
      );
      await _pump(tester, repo);
      await tester.pumpAndSettle();
      expect(find.text('已完成的阅读'), findsNothing);
      expect(find.text('下周预习'), findsNothing);
      await _tap(tester, '全部任务');
      expect(find.text('已完成的阅读'), findsOneWidget);
      expect(find.text('下周预习'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('AI 处理列表'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('AI 处理列表'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TaskListPage>(find.byType(TaskListPage)).kind,
        TaskListKind.activeFlow,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading, failure with retry, empty states and learning events', (
    tester,
  ) async {
    final repo = _Tasks()..pending = Completer<LearningDashboard>();
    await _pump(tester, repo);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.pending!.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('任务中心加载失败'), findsOneWidget);
    repo.pending = null;
    await _tap(tester, '重试');
    expect(find.textContaining('今天暂无待办任务'), findsOneWidget);
    expect(find.textContaining('暂无推荐复习'), findsOneWidget);
    final loads = repo.loads;
    LearningEvents.notify();
    await tester.pumpAndSettle();
    expect(repo.loads, loads + 1);
    await tester.pumpWidget(const SizedBox());
    LearningEvents.notify();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'existing notifiers refresh on activation and active-tab changes',
    (tester) async {
      final repo = _Tasks();
      final refresh = ValueNotifier(0);
      final active = ValueNotifier(0);
      addTearDown(refresh.dispose);
      addTearDown(active.dispose);
      await _pump(tester, repo, refresh: refresh, active: active);
      await tester.pumpAndSettle();
      refresh.value++;
      LearningEvents.notify();
      await tester.pumpAndSettle();
      expect(repo.loads, 1);
      active.value = 2;
      await tester.pumpAndSettle();
      expect(repo.loads, 2);
      refresh.value++;
      await tester.pumpAndSettle();
      expect(repo.loads, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'personal creation validates title and stores estimated pomodoros in SQLite',
    (tester) async {
      sqfliteFfiInit();
      final app = await tester.runAsync(
        () => AppDatabase.openForTesting(databaseFactoryFfi),
      );
      final db = await app!.database;
      addTearDown(db.close);
      await tester.runAsync(
        () => db.insert('users', {
          'id': 1,
          'username': 'fixture',
          'password_hash': 'fixture',
          'password_salt': 'fixture',
          'created_at': '2026-10-15T00:00:00Z',
          'updated_at': '2026-10-15T00:00:00Z',
        }),
      );
      final repo = LearningTaskRepository(database: app);
      Future<void> settleDatabase() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await _pump(tester, repo);
      await settleDatabase();
      await _tap(tester, '新建学习任务');
      await _tap(tester, '创建任务');
      expect(find.text('请输入任务名称'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  复习第一章  ');
      await tester.tap(find.byTooltip('增加番茄数'));
      await tester.tap(find.byTooltip('增加番茄数'));
      await tester.tap(find.text('创建任务'));
      await settleDatabase();
      final rows = await tester.runAsync(
        () => db.query('pomodoro_tasks', where: 'user_id=?', whereArgs: [1]),
      );
      expect(rows, hasLength(1));
      expect(rows!.single['title'], '复习第一章');
      expect(rows.single['estimated_pomodoros'], 3);
      expect(rows.single['status'], 'pending');
      expect(find.text('复习第一章'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
