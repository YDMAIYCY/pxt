// Explicitly invoked live journey. Uses real accounts, repositories and APIs.
// Native secure storage and paths are replaced only in this isolated host runner.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pxt1/community/app_account_repository.dart';
import 'package:pxt1/community/cloud_backend.dart';
import 'package:pxt1/community/community_repository.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/ui/pages/login_page.dart';
import 'package:pxt1/ui/pages/home_page.dart';
import 'package:pxt1/ui/pages/book_library_page.dart';
import 'package:pxt1/ui/pages/community/publish_question_page.dart';
import 'package:pxt1/ui/pages/community/question_detail_page.dart';
import 'package:pxt1/ui/pages/community/social_pages.dart';
import 'package:pxt1/ui/pages/community/chat_page.dart';
import 'package:pxt1/ui/pages/tabs/tasks_tab_page.dart';
import 'package:pxt1/ui/pages/llm_config_edit_page.dart';
import 'package:pxt1/ui/pages/library_practice_page.dart';
import 'package:pxt1/ui/pages/ocr_result_page.dart';
import 'package:pxt1/ui/pages/ai_generation_page.dart';
import 'package:pxt1/ui/pages/tabs/focus_tab_page.dart';
import 'package:pxt1/database/practice_session_repository.dart';
import 'package:pxt1/ui/pages/qsclaw_agent_page.dart';
import 'package:pxt1/agent/eclaw_context.dart';
import 'package:pxt1/ui/pages/interview/interview_prepare_page.dart';
import 'package:pxt1/ui/pages/interview/interview_chat_page.dart';
import 'package:pxt1/database/interview_repository.dart';
import 'package:pxt1/interview/interview_controller.dart';
import 'package:pxt1/interview/interview_evidence_service.dart';
import 'package:pxt1/interview/interview_voice_port.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

const questions = [
  (
    title: '[联调测试] Dijkstra 为什么要求边权非负？',
    body:
        '【用户流程联调数据，供学习讨论】\n学习最短路径时，我理解 Dijkstra 每轮确定当前距离最小的未访问顶点；但为什么一旦存在负权边，这个确定动作就可能出错？\n例如 S→A 权重 2，S→B 权重 5，B→A 权重 -4，此时 S 到 A 的最短距离是 1。请结合处理顺序解释错误，并说明 Bellman-Ford 如何处理负权边，以及负环检测的依据。',
    tags: '数据结构,最短路径,算法',
    answer:
        '【联调测试回答】Dijkstra 的正确性依赖：一条路径在继续延伸时，非负边不会让距离变小。例子中先确定 A 的距离为 2；随后访问 B 才得到 5-4=1，推翻了已确定的距离。Bellman-Ford 反复松弛所有边，V-1 轮足以覆盖不含环的最短简单路径；若从源点可达的边在第 V 轮仍可松弛，则存在源点可达的负环。负环影响的顶点不存在有限最短距离。',
  ),
  (
    title: '[联调测试] 数据库复合索引的最左前缀如何影响查询？',
    body:
        '【用户流程联调数据，供学习讨论】\n订单表有联合索引 (user_id, status, created_at)。三个查询分别为：① user_id=7 AND status=1，② status=1，③ user_id=7 AND created_at>某时刻。\n为什么这些条件利用索引的方式不同？第三种条件没有给出 status 时，created_at 能否直接缩小连续的索引扫描范围？请区分索引查找、扫描过滤、覆盖索引，并说明应如何用 EXPLAIN 验证，而不是只凭“用了索引”判断效率。',
    tags: '数据库,索引,SQL',
    answer:
        '【联调测试回答】B-tree 联合索引按 user_id、status、created_at 的顺序排序。①可使用前两列定位；②通常不能依靠最左前缀直接定位，是否采用扫描或跳跃扫描取决于具体数据库和优化器。③可先按 user_id 定位，但缺少 status 条件时，created_at 在不同 status 分组内各自有序，通常不能形成单一连续范围。后续条件可能作为过滤。覆盖索引表示查询所需列都可从索引取得，和是否有效缩小扫描范围是两回事。应比较 EXPLAIN 中访问方式、使用的索引列、估算/实际行数，并结合 EXPLAIN ANALYZE 观察实际成本。',
  ),
  (
    title: '[联调测试] 如何避免机器学习交叉验证中的数据泄漏？',
    body:
        '【用户流程联调数据，供学习讨论】\n做分类任务时，如果先对全部数据拟合 StandardScaler 或做特征筛选，再进行交叉验证，为什么会得到偏乐观的分数？\n我理解验证折应该模拟未见样本。请解释标准化、特征筛选、超参数选择各自应该放在哪一步；如果同一个人的多条记录同时存在，应如何划分？如果数据有时间顺序，为什么随机划分还可能产生泄漏？',
    tags: '机器学习,交叉验证,数据泄漏',
    answer:
        '【联调测试回答】验证折必须独立于训练过程。全量拟合标准化器或筛选特征，会让验证数据的分布或标签信息参与训练。应在每个训练折内部拟合预处理与特征选择，再仅对验证折执行 transform，可用 Pipeline 管理。超参数选择放在内层交叉验证，外层用于估计泛化表现。多人多记录数据应按人分组划分，避免同一人的记录跨训练和验证；时间数据按时间向前划分，保证预测时只使用当时可获得的信息。最终测试集在流程确定后仅用于最终评估。',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  testWidgets(
    'real users: learning, AI practice and community journey',
    (tester) async {
      const reusePath = String.fromEnvironment('LIVE_RUN_DIRECTORY');
      const extended = bool.fromEnvironment('LIVE_EXTENDED');
      const auxiliary = bool.fromEnvironment('LIVE_AUX');
      const finalChecks = bool.fromEnvironment('LIVE_FINAL');
      final root = Directory(
        reusePath.isEmpty
            ? 'build/live-user-test/${DateTime.now().millisecondsSinceEpoch}'
            : reusePath,
      ).absolute;
      await tester.runAsync(() => root.create(recursive: true));
      final secret =
          jsonDecode(
                (await tester.runAsync(
                  () => File('config/community-test.local.json').readAsString(),
                ))!,
              )
              as Map;
      final cloud =
          jsonDecode(
                (await tester.runAsync(
                  () => File('config/supabase.local.json').readAsString(),
                ))!,
              )
              as Map;
      final model =
          jsonDecode(
                (await tester.runAsync(
                  () => File(
                    'build/live-user-test/model.local.json',
                  ).readAsString(),
                ))!,
              )
              as Map;
      final report = <String, dynamic>{
        'started': DateTime.now().toIso8601String(),
        'runner':
            'Flutter host UI; real SQLite and remote services; simulated native storage/paths',
        'steps': <Map<String, dynamic>>[],
      };
      final steps = report['steps'] as List;
      final capture = GlobalKey();
      final ids = <String>[];
      String? userA, userB, conversation;
      final localIds = <String, int>{};
      final libraryIds = <String, int>{};
      final reportName = finalChecks
          ? 'final-report'
          : auxiliary
          ? 'auxiliary-report'
          : extended
          ? 'extended-report'
          : 'report';
      Future<void> writeReport() async {
        await tester.runAsync(
          () => File(
            '${root.path}/$reportName.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(report)),
        );
      }

      Future<void> drain([int n = 5]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 120)),
          );
          await tester.pump(const Duration(milliseconds: 150));
        }
      }

      Future<void> waitFor(
        bool Function() ready,
        String description, {
        int seconds = 45,
      }) async {
        final watch = Stopwatch()..start();
        while (!ready() && watch.elapsed.inSeconds < seconds) {
          await drain(1);
        }
        if (!ready()) {
          throw StateError(
            'Timed out: $description; visible texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(' | ')}',
          );
        }
      }

      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      Future<void> reveal(Finder f) async {
        if (f.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            f,
            300,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 35,
          );
        }
        await tester.ensureVisible(f.first);
        await tester.pump();
      }

      Future<void> tap(Finder f) async {
        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await drain(1);
        await reveal(f);
        await drain(1);
        for (
          var i = 0;
          i < 8 && f.first.hitTestable().evaluate().isEmpty;
          i++
        ) {
          final center = tester.getCenter(f.first);
          await tester.drag(
            find.byType(Scrollable).first,
            Offset(0, center.dy > 850 ? -220 : 220),
          );
          await drain(2);
        }
        await tester.runAsync(() async {
          await tester.tap(f.first);
        });
        await drain();
      }

      Future<void> mount(Widget page) async {
        const font = 'Microsoft YaHei';
        final base = AppTheme.light;
        final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: font),
          primaryTextTheme: base.primaryTextTheme.apply(fontFamily: font),
          appBarTheme: base.appBarTheme.copyWith(
            titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
              fontFamily: font,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: base.filledButtonTheme.style?.copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontFamily: font),
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: base.textButtonTheme.style?.copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontFamily: font),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              key: UniqueKey(),
              theme: theme,
              home: Scaffold(body: page),
              routes: {
                HomePage.routeName: (_) => const HomePage(),
                LoginPage.routeName: (_) => const LoginPage(),
              },
            ),
          ),
        );
        await drain();
      }

      Future<void> screenshot(String name) async {
        await drain(3);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${root.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      Future<void> step(String name, Future<void> Function() action) async {
        final watch = Stopwatch()..start();
        final entry = <String, dynamic>{'name': name};
        steps.add(entry);
        print('LIVE starting: $name');
        try {
          await action();
          entry['status'] = 'passed';
        } catch (e, st) {
          entry['status'] = 'failed';
          entry['error'] = e.toString().replaceAll(
            model['apiKey'] as String,
            '[REDACTED]',
          );
          entry['stack'] = st.toString().split('\n').take(5).join('\n');
          try {
            await screenshot('failure_${steps.length}');
          } catch (_) {}
        }
        final uiError = tester.takeException();
        if (uiError != null) {
          entry['uiError'] = uiError.toString();
          entry['status'] = 'failed';
        }
        entry['milliseconds'] = watch.elapsedMilliseconds;
        await writeReport();
        print(
          'LIVE ${entry['status']}: $name${entry['error'] == null ? '' : ' — ${entry['error']}'}',
        );
      }

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      FlutterSecureStorage.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path,
          );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await tester.runAsync(() => databaseFactory.setDatabasesPath(root.path));
      final db = (await tester.runAsync(() => AppDatabase.instance.database))!;
      final client = SupabaseClient(
        cloud['SUPABASE_URL'] as String,
        cloud['SUPABASE_PUBLISHABLE_KEY'] as String,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      CloudBackend.instance.client = client;
      final repo = CommunityRepository();
      await tester.runAsync(() async {
        for (final family in ['Roboto', 'Ahem', 'Microsoft YaHei']) {
          await (FontLoader(family)..addFont(
                Future.value(
                  ByteData.sublistView(
                    await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
                  ),
                ),
              ))
              .load();
        }
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(
                ByteData.sublistView(
                  await File(
                    'D:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
                  ).readAsBytes(),
                ),
              ),
            ))
            .load();
      });
      print('LIVE bootstrap ready');

      Future<void> login(String name, String suffix) async {
        await tester.pumpWidget(const SizedBox());
        await drain(2);
        if (client.auth.currentSession != null) {
          await tester.runAsync(() => AuthRepository().logoutCurrentUser());
        }
        await mount(const LoginPage());
        await waitFor(
          () =>
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('submit-account')),
                  )
                  .onPressed !=
              null,
          'login form initialized',
        );
        await tester.enterText(
          find.byKey(const ValueKey('email')),
          secret['COMMUNITY_TEST_EMAIL_$suffix'] as String,
        );
        await tester.enterText(
          find.byKey(const ValueKey('password')),
          secret['COMMUNITY_TEST_PASSWORD_$suffix'] as String,
        );
        await tap(find.byKey(const ValueKey('submit-account')));
        await waitFor(
          () =>
              find.byType(HomePage).evaluate().isNotEmpty &&
              find.text('社区').evaluate().isNotEmpty,
          '$name logged into home',
        );
        final p = await tester.runAsync(
          () => AuthRepository().getCurrentUserProfile(),
        );
        if (p == null || client.auth.currentUser == null) {
          throw StateError('No verified login');
        }
        localIds[name] = p.id;
        if (name == 'yk') {
          userA = client.auth.currentUser!.id;
        } else {
          userB = client.auth.currentUser!.id;
        }
        final restored = await tester.runAsync(
          () => AppAccountRepository().restoreSession(),
        );
        expect(restored?.id, p.id);
        await screenshot('${name}_home');
      }

      Future<void> createLibraryAndTask(String name) async {
        await mount(const BookLibraryPage());
        await waitFor(
          () => find.text('添加').evaluate().isNotEmpty,
          'library shelf',
        );
        await tap(find.text('添加'));
        await tap(find.text('手动创建知识库'));
        await tap(find.text('继续'));
        await tester.enterText(field('知识库名称'), '$name · 计算机专业学习');
        await tap(find.text('创建知识库'));
        await waitFor(
          () => find.text('$name · 计算机专业学习').evaluate().isNotEmpty,
          'created library appears',
        );
        final libs = await tester.runAsync(
          () => KnowledgeLibraryRepository().fetchLibraries(localIds[name]!),
        );
        libraryIds[name] = libs!
            .singleWhere((l) => l.name == '$name · 计算机专业学习')
            .id;
        await screenshot('${name}_libraries');
        await mount(const TasksTabPage());
        await waitFor(
          () => find.text('新建学习任务').evaluate().isNotEmpty,
          'task dashboard',
        );
        await tap(find.text('新建学习任务'));
        await tester.enterText(field('任务名称'), '复习最短路径算法与索引原理');
        await tap(find.text('创建任务'));
        await waitFor(
          () => find.text('复习最短路径算法与索引原理').evaluate().isNotEmpty,
          'task persisted',
        );
        final rows = await tester.runAsync(
          () => db.query(
            'pomodoro_tasks',
            where: 'user_id=?',
            whereArgs: [localIds[name]],
          ),
        );
        expect(rows, isNotEmpty);
        await screenshot('${name}_tasks');
      }

      Future<void> configureModel(String name) async {
        final now = DateTime.now();
        final config = LlmProviderConfig(
          id: null,
          userId: localIds[name]!,
          provider: model['provider'] as String,
          apiMode: LlmApiMode.openAiCompatible,
          apiKey: model['apiKey'] as String,
          baseUrl: model['baseUrl'] as String,
          model: model['model'] as String,
          maxTokens: 8192,
          createdAt: now,
          updatedAt: now,
        );
        await mount(LlmConfigEditPage(config: config));
        await waitFor(
          () => find.text('服务配置').evaluate().isNotEmpty,
          'model settings',
        );
        await tap(find.text('温度、最大 Tokens、连接测试与响应格式'));
        await tap(find.text('测试连接'));
        await waitFor(
          () =>
              find.textContaining('连接成功').evaluate().isNotEmpty ||
              find.textContaining('连接失败').evaluate().isNotEmpty,
          'real model connection',
          seconds: 110,
        );
        expect(find.textContaining('连接成功'), findsOneWidget);
        await screenshot('${name}_model_connected');
        await tap(find.text('保存'));
        final saved = await tester.runAsync(
          () => LlmConfigRepository().getByUserId(localIds[name]!),
        );
        expect(saved?.model, model['model']);
      }

      Future<void> finish() async {
        await tester.pumpWidget(const SizedBox());
        await drain(3);
        report['database'] = db.path;
        report['localIds'] = localIds;
        report['libraryIds'] = libraryIds;
        report['counts'] = {};
        for (final table in [
          'users',
          'knowledge_libraries',
          'source_documents',
          'knowledge_cards',
          'review_outlines',
          'mindmap_texts',
          'practice_questions',
          'practice_submissions',
          'pomodoro_tasks',
          'pomodoro_records',
          'checkin_records',
        ]) {
          try {
            report['counts'][table] = (await tester.runAsync(
              () => db.rawQuery('SELECT COUNT(*) AS n FROM $table'),
            ))!.first['n'];
          } catch (_) {}
        }
        report['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
        await writeReport();
        await tester.runAsync(
          () => client.dispose().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          ),
        );
        await drain(3);
        await tester.runAsync(() => db.close());
        print('LIVE_REPORT ${root.path}/$reportName.json');
        expect(
          steps
              .where((s) => s['status'] == 'failed')
              .map((s) => s['name'])
              .toList(),
          isEmpty,
          reason:
              'Each recorded live journey step must pass; see the report for failures.',
        );
      }

      if (finalChecks) {
        await step('最终补验登录与真实 GLM 配置', () async {
          await login('zdd', 'B');
          await configureModel('zdd');
        });
        final libs = await tester.runAsync(
          () => KnowledgeLibraryRepository().fetchLibraries(localIds['zdd']!),
        );
        final lib = libs!.firstWhere((l) => l.name == 'zdd · 计算机专业学习');
        libraryIds['zdd'] = lib.id;
        await step('专注开始、暂停、恢复、结束及打卡', () async {
          final tasks = await tester.runAsync(
            () => db.query(
              'pomodoro_tasks',
              where: 'user_id=? AND title=?',
              whereArgs: [localIds['zdd'], '复习最短路径算法与索引原理'],
            ),
          );
          await mount(FocusTabPage(initialTaskId: tasks!.first['id'] as int));
          await waitFor(
            () => find.text('开始专注').evaluate().isNotEmpty,
            'focus task loaded',
          );
          await tap(find.text('开始专注'));
          await waitFor(
            () => find.text('暂停').evaluate().isNotEmpty,
            'focus running',
          );
          await drain(20);
          await tap(find.text('暂停'));
          await waitFor(
            () => find.text('继续').evaluate().isNotEmpty,
            'focus paused',
          );
          await tap(find.text('继续'));
          await drain(15);
          await tap(find.text('结束'));
          await waitFor(
            () => find.text('开始专注').evaluate().isNotEmpty,
            'focus completed',
          );
          if (find.text('打卡').evaluate().isNotEmpty) await tap(find.text('打卡'));
          final records = await tester.runAsync(
            () => db.query(
              'pomodoro_records',
              where: 'user_id=?',
              whereArgs: [localIds['zdd']],
            ),
          );
          expect(records, isNotEmpty);
          report['focusRecords'] = records;
          await screenshot('focus_final');
        });
        await step('无语音路径：GLM 面试出题、文字评分与结果报告', () async {
          final docs = await tester.runAsync(
            () => db.query(
              'source_documents',
              where: "user_id=? AND ocr_status='success'",
              whereArgs: [localIds['zdd']],
            ),
          );
          final record = docs!.first['import_record_id'] as int;
          final repo = InterviewRepository();
          final prior = await tester.runAsync(() => repo.listSessions(localIds['zdd']!, libraryId:lib.id, recordId:record));
          final resumed = prior!.where((s)=>s.status=='in_progress' && !s.voiceEnabled).firstOrNull;
          final session = await tester.runAsync(
            () async => resumed ?? await repo.createSession(
              userId: localIds['zdd']!,
              libraryId: lib.id,
              recordId: record,
              scopeName: 'Dijkstra 最短路径原理',
              mode: 'basic',
              difficulty: 'medium',
              targetQuestionCount: 3,
              voiceEnabled: false,
              autoPlay: false,
            ),
          );
          final config = await tester.runAsync(
            () => LlmConfigRepository().getByUserId(localIds['zdd']!),
          );
          final controller = InterviewController(
            userId: localIds['zdd']!,
            session: session!,
            repository: repo,
            voice: NoopInterviewVoice(),
            evidenceService: InterviewEvidenceService(),
            llmConfig: config,
          );
          await mount(
            InterviewChatPage(
              userId: localIds['zdd']!,
              sessionId: session.id,
              controller: controller,
            ),
          );
          await waitFor(
            () => controller.canRecord,
            'real interview questions ready',
            seconds: 160,
          );
          final qs = await tester.runAsync(
            () => db.query(
              'interview_questions',
              where: 'session_id=?',
              whereArgs: [session.id],
            ),
          );
          expect(qs!.length, 3);
          report['interviewSession'] = session.id;
          report['interviewQuestionCount'] = qs.length;
          await tap(find.byTooltip('文字回答'));
          await waitFor(
            () => find.byType(TextField).evaluate().isNotEmpty,
            'text interview answer',
          );
          await tester.enterText(
            find.byType(TextField),
            questions.first.answer.replaceAll('【联调测试回答】', ''),
          );
          await tap(find.text('提交回答'));
          final watch = Stopwatch()..start();
          List<Map<String, Object?>> evaluations = [];
          while (watch.elapsed.inSeconds < 150) {
            await drain(4);
            evaluations =
                (await tester.runAsync(
                  () => db.query(
                    'interview_evaluations',
                    where: 'session_id=?',
                    whereArgs: [session.id],
                  ),
                )) ??
                [];
            if (evaluations.isNotEmpty) break;
          }
          expect(evaluations, isNotEmpty);
          report['interviewEvaluationCount'] = evaluations.length;
          report['interviewScore'] = evaluations.first['total_score'];
          await screenshot('interview_scored_final');
          await waitFor(
            () =>
                controller.canRecord ||
                controller.hasPendingAnswer ||
                controller.isFinished,
            'evaluation complete',
          );
          await tap(find.byTooltip('面试操作'));
          await tap(find.text('结束面试'));
          await tap(find.text('结束并生成报告'));
          await drain(10);
          final saved = await tester.runAsync(
            () => db.query(
              'interview_sessions',
              where: 'id=?',
              whereArgs: [session.id],
            ),
          );
          expect(saved!.single['report_json'], isNotNull);
          report['interviewStatus'] = saved.single['status'];
          await screenshot('interview_report_final');
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await drain(3);
        });
        await step('四类 AI 结果最终状态核对', () async {
          final jobs = await tester.runAsync(
            () => db.query(
              'ai_generation_tasks',
              columns: ['task_type', 'status', 'error_message'],
            ),
          );
          expect(
            jobs!.map((j) => j['task_type']).toSet(),
            containsAll([
              'knowledge_cards',
              'review_outline',
              'mindmap_text',
              'practice_questions',
            ]),
          );
          expect(jobs.every((j) => j['status'] == 'completed'), isTrue);
          report['generationTasksFinal'] = jobs;
        });
        await finish();
        return;
      }
      if (auxiliary) {
        await step('zdd 真实登录并配置 GLM', () async {
          await login('zdd', 'B');
          await configureModel('zdd');
        });
        final libs = await tester.runAsync(
          () => KnowledgeLibraryRepository().fetchLibraries(localIds['zdd']!),
        );
        libraryIds['zdd'] = libs!
            .firstWhere((l) => l.name == 'zdd · 计算机专业学习')
            .id;
        final docs = await tester.runAsync(
          () => db.query(
            'source_documents',
            where: 'user_id=?',
            whereArgs: [localIds['zdd']],
          ),
        );
        final document = docs!.first['id'] as int;
        for (final pair in [
          ('knowledge_cards', '知识卡片'),
          ('review_outline', '复习提纲'),
          ('mindmap_text', '思维导图文字版'),
          ('practice_questions', '练习题'),
        ]) {
          await step('验证真实生成结果：${pair.$2}', () async {
            var jobs = await tester.runAsync(
              () => db.query(
                'ai_generation_tasks',
                where: 'document_id=? AND task_type=?',
                whereArgs: [document, pair.$1],
              ),
            );
            if (jobs!.any((j) => j['status'] == 'completed')) return;
            await mount(AiGenerationPage(documentId: document));
            await waitFor(
              () => find.text('一键生成全部').evaluate().isNotEmpty,
              'generation controls',
            );
            final card = find.byWidgetPredicate(
              (w) =>
                  w.runtimeType.toString() == '_TaskActionCard' &&
                  (w as dynamic).taskType == pair.$1,
            );
            await reveal(card);
            final button = find.descendant(
              of: card,
              matching: find.byWidgetPredicate(
                (w) => w is OutlinedButton || w is FilledButton,
              ),
            );
            await tap(button);
            final watch = Stopwatch()..start();
            while (watch.elapsed.inSeconds < 150) {
              await drain(4);
              jobs = await tester.runAsync(
                () => db.query(
                  'ai_generation_tasks',
                  where: 'document_id=? AND task_type=?',
                  whereArgs: [document, pair.$1],
                ),
              );
              if (jobs!.any(
                (j) => j['status'] == 'completed' || j['status'] == 'failed',
              )) {
                break;
              }
            }
            expect(
              jobs!.any((j) => j['status'] == 'completed'),
              isTrue,
              reason: 'Actual GLM output must be persisted',
            );
          });
        }
        report['generationTasksFinal'] = await tester.runAsync(
          () => db.query(
            'ai_generation_tasks',
            columns: ['task_type', 'status', 'error_message'],
            where: 'document_id=?',
            whereArgs: [document],
          ),
        );
        await step('专注选择任务后开始、暂停、继续、结束并打卡', () async {
          await mount(const FocusTabPage());
          await waitFor(
            () => find.text('开始专注').evaluate().isNotEmpty,
            'focus ready',
          );
          await tap(find.text('选择任务'));
          await waitFor(
            () => find.text('选择专注任务').evaluate().isNotEmpty,
            'focus task picker',
          );
          await tap(find.text('复习最短路径算法与索引原理'));
          await tap(find.text('开始专注'));
          await drain(15);
          await tap(find.text('暂停'));
          await tap(find.text('继续'));
          await drain(12);
          await tap(find.text('结束'));
          await drain(6);
          if (find.text('打卡').evaluate().isNotEmpty) await tap(find.text('打卡'));
          final records = await tester.runAsync(
            () => db.query(
              'pomodoro_records',
              where: 'user_id=?',
              whereArgs: [localIds['zdd']],
            ),
          );
          expect(records, isNotEmpty);
          await screenshot('focus_completed');
        });
        await step('EClaw 基于当前知识库进行真实 GLM 问答', () async {
          await mount(
            QsClawAgentPage(
              initialContext: EClawContext(
                knowledgeBaseId: libraryIds['zdd'],
                documentId: document,
              ),
            ),
          );
          await waitFor(
            () => find.byType(TextField).evaluate().isNotEmpty,
            'EClaw input',
          );
          await tester.enterText(
            find.byType(TextField),
            '请结合当前资料解释 Dijkstra 算法为什么要求边权非负，并用 S 到 A 为 2、S 到 B 为 5、B 到 A 为 -4 的例子说明。',
          );
          await tap(find.byTooltip('发送'));
          final watch = Stopwatch()..start();
          List<Map<String, Object?>> replies = [];
          while (watch.elapsed.inSeconds < 150) {
            await drain(4);
            replies =
                (await tester.runAsync(
                  () => db.query(
                    'ai_chat_messages',
                    where: "role='assistant' AND model=?",
                    whereArgs: [model['model']],
                  ),
                )) ??
                [];
            if (replies.any((r) => (r['content'] as String).length > 25)) break;
          }
          expect(replies, isNotEmpty);
          report['assistantReplyCount'] = replies.length;
          await screenshot('eclaw_real_reply');
        });
        await step('AI 面试真实出题与文字作答评分', () async {
          await mount(
            InterviewPreparePage(
              userId: localIds['zdd']!,
              libraryId: libraryIds['zdd'],
            ),
          );
          await waitFor(
            () => find.text('3 题').evaluate().isNotEmpty,
            'interview preparation',
          );
          await tap(find.text('3 题'));
          await reveal(find.text('AI 面试官语音'));
          final row = find
              .ancestor(of: find.text('AI 面试官语音'), matching: find.byType(Row))
              .first;
          await tap(find.descendant(of: row, matching: find.byType(Switch)));
          await tap(find.text('开始 AI 面试'));
          await waitFor(
            () => find.byType(InterviewChatPage).evaluate().isNotEmpty,
            'interview starts',
            seconds: 60,
          );
          await waitFor(
            () => find.text('文字回答').evaluate().isNotEmpty,
            'real interview question',
            seconds: 160,
          );
          var sessions = await tester.runAsync(
            () => db.query('interview_sessions', orderBy: 'id DESC', limit: 1),
          );
          final sid = sessions!.single['id'];
          report['interviewSession'] = sid;
          final qs = await tester.runAsync(
            () => db.query(
              'interview_questions',
              where: 'session_id=?',
              whereArgs: [sid],
            ),
          );
          expect(qs!.length, 3);
          await tap(find.byTooltip('文字回答'));
          await waitFor(
            () => find.byType(TextField).evaluate().isNotEmpty,
            'text answer field',
          );
          await tester.enterText(
            find.byType(TextField),
            'Dijkstra 每次确定当前距离最小的未访问顶点，正确性依赖非负边权。示例先确定 A 的距离为 2，但后续经过 B 的路径长度为 5-4=1，说明贪心确定可能错误。Bellman-Ford 通过反复松弛所有边处理负权边；V-1 轮后仍可松弛，说明有从源点可达的负环，受影响顶点不存在有限最短距离。',
          );
          await tap(find.text('提交回答'));
          final watch = Stopwatch()..start();
          List<Map<String, Object?>> evaluations = [];
          while (watch.elapsed.inSeconds < 160) {
            await drain(4);
            evaluations =
                (await tester.runAsync(
                  () => db.query(
                    'interview_evaluations',
                    where: 'session_id=?',
                    whereArgs: [sid],
                  ),
                )) ??
                [];
            if (evaluations.isNotEmpty) break;
          }
          expect(evaluations, isNotEmpty);
          report['interviewEvaluationCount'] = evaluations.length;
          report['interviewFirstScore'] = evaluations.first['total_score'];
          await screenshot('interview_scored');
          await tap(find.byTooltip('面试操作'));
          await tap(find.text('结束面试'));
          await tap(find.text('结束并生成报告'));
          await drain(8);
          sessions = await tester.runAsync(
            () =>
                db.query('interview_sessions', where: 'id=?', whereArgs: [sid]),
          );
          expect(sessions!.single['report_json'], isNotNull);
          await screenshot('interview_report');
        });
        final published = await tester.runAsync(
          () => client
              .from('community_questions')
              .select('id,title,author_id')
              .inFilter('title', questions.map((q) => q.title).toList()),
        );
        report['cloudQuestions'] = published;
        if (published!.length > 1) {
          await step('复现社区资料保存后直接组卷的衔接问题', () async {
            final qid = published[1]['id'] as String;
            await mount(QuestionDetailPage(questionId: qid));
            await waitFor(
              () => find.text('存入知识库').evaluate().isNotEmpty,
              'save another community question',
            );
            await tap(find.text('存入知识库').first);
            await waitFor(
              () => find.text('保存到我的知识库').evaluate().isNotEmpty,
              'library picker',
            );
            await tap(find.text('zdd · 计算机专业学习'));
            await drain(8);
            final saves = await tester.runAsync(
              () => db.query(
                'community_knowledge_saves',
                where: 'user_id=? AND question_id=?',
                whereArgs: [localIds['zdd'], qid],
              ),
            );
            final newDoc = saves!.first['document_id'] as int;
            await mount(
              LibraryPracticePage(
                libraryId: libraryIds['zdd'],
                documentId: newDoc,
              ),
            );
            await waitFor(
              () => find.text('练习范围').evaluate().isNotEmpty,
              'new source practice',
            );
            await tap(find.text('基于所选范围组卷'));
            await waitFor(
              () => find.textContaining('没有已解析资料').evaluate().isNotEmpty,
              'source compatibility error',
              seconds: 15,
            );
            report['confirmedDefects'] = [
              {
                'feature': '社区资料存入知识库后直接组卷',
                'documentId': newDoc,
                'actual': '资料已保存，但组卷提示所选范围没有已解析资料',
                'cause':
                    'community source ocr_status=completed while practice sourceSnapshot accepts success',
                'workaround': '在文本校对页保存修改后可以组卷',
              },
            ];
            await screenshot('defect_community_practice');
          });
        }
        for (final q in published) {
          await step('复核云端问题及回答：${q['title']}', () async {
            final answers = await tester.runAsync(
              () => repo.answers(q['id'] as String),
            );
            expect(answers, isNotEmpty);
            report['cloudAnswerCount_${q['id']}'] = answers!.length;
          });
        }
        await step('社区页面显示真实问题与回答', () async {
          await mount(
            QuestionDetailPage(questionId: published.first['id'] as String),
          );
          await waitFor(
            () => find
                .text(published.first['title'] as String)
                .evaluate()
                .isNotEmpty,
            'question final render',
          );
          await drain(12);
          await screenshot('community_final');
        });
        await finish();
        return;
      }
      if (extended) {
        await step('zdd 重新登录既有测试空间', () => login('zdd', 'B'));
        final libs = await tester.runAsync(
          () => KnowledgeLibraryRepository().fetchLibraries(localIds['zdd']!),
        );
        libraryIds['zdd'] = libs!
            .firstWhere((l) => l.name == 'zdd · 计算机专业学习')
            .id;
        final published = await tester.runAsync(
          () => client
              .from('community_questions')
              .select('id,title,author_id')
              .inFilter('title', questions.map((q) => q.title).toList()),
        );
        for (final q in questions) {
          final row = published!
              .where((p) => p['title'] == q.title)
              .firstOrNull;
          if (row != null) {
            ids.add(row['id'] as String);
            userA = row['author_id'] as String;
          }
        }
        for (var i = 0; i < ids.length; i++) {
          await step('zdd 完成专业问题回答 ${i + 1}', () async {
            final old = await tester.runAsync(() => repo.answers(ids[i]));
            if (old!.any(
              (a) =>
                  a['author_id'] == userB && a['body'] == questions[i].answer,
            )) {
              return;
            }
            await mount(QuestionDetailPage(questionId: ids[i]));
            await waitFor(
              () => find.text(questions[i].title).evaluate().isNotEmpty,
              'question loaded',
            );
            await reveal(field('写下你的回答'));
            await tester.enterText(field('写下你的回答'), questions[i].answer);
            await tap(find.text('发布回答'));
            await drain(10);
            final answers = await tester.runAsync(() => repo.answers(ids[i]));
            expect(
              answers!.any(
                (a) =>
                    a['author_id'] == userB && a['body'] == questions[i].answer,
              ),
              isTrue,
            );
            await screenshot('answered_${i + 1}');
          });
        }
        await step('zdd 界面验证并保存 GLM 配置', () => configureModel('zdd'));
        final sources = await tester.runAsync(
          () => db.query(
            'source_documents',
            where: 'user_id=?',
            whereArgs: [localIds['zdd']],
          ),
        );
        int? document = sources!.firstOrNull?['id'] as int?;
        if (document != null) {
          await step('社区资料通过文本校对界面确认后可供 AI 使用', () async {
            report['sourceStatusBeforeCorrection'] =
                sources.first['ocr_status'];
            await mount(OcrResultPage(documentId: document));
            await waitFor(
              () => find.text('保存修改').evaluate().isNotEmpty,
              'text correction page',
            );
            await tap(find.text('保存修改'));
            await drain(5);
            final rows = await tester.runAsync(
              () => db.query(
                'source_documents',
                where: 'id=?',
                whereArgs: [document],
              ),
            );
            expect(rows!.single['ocr_status'], 'success');
            await screenshot('source_corrected');
          });
          await step('GLM 真实生成五道专项题并持久化', () async {
            await mount(LibraryPracticePage(libraryId: libraryIds['zdd']));
            await waitFor(
              () => find.text('练习范围').evaluate().isNotEmpty,
              'practice scope',
            );
            await tap(find.text('基于所选范围组卷'));
            final watch = Stopwatch()..start();
            while (find.byType(ScopedPracticeRunner).evaluate().isEmpty &&
                watch.elapsed.inSeconds < 160) {
              await drain(3);
            }
            expect(find.byType(ScopedPracticeRunner), findsOneWidget);
            final rows = await tester.runAsync(
              () => db.query('practice_questions'),
            );
            report['generatedQuestions'] = rows!.length;
            expect(rows.length, greaterThanOrEqualTo(5));
            await screenshot('practice_generated');
          });
          await step('真实练习界面作答：正确、错误和错题记录', () async {
            final scope = PracticeScope(
              userId: localIds['zdd']!,
              libraryId: libraryIds['zdd'],
            );
            final list = await tester.runAsync(
              () => PracticeSessionRepository().questions(scope),
            );
            expect(list, isNotEmpty);
            await mount(ScopedPracticeRunner(scope: scope, questions: list!));
            for (var i = 0; i < list.length && i < 5; i++) {
              await reveal(field('我的答案'));
              final q = list[i].question;
              var answer = q.answerText ?? '关键原理';
              final wrong = i.isOdd;
              if (wrong) {
                answer = q.questionKind == 'multiple_choice'
                    ? (answer.trim() == 'A' ? 'B' : 'A')
                    : q.questionKind == 'true_false'
                    ? (answer.trim() == '对' ? '错' : '对')
                    : '这道题我暂时不会';
              }
              await tester.enterText(field('我的答案'), answer);
              await tap(find.text('提交并核对'));
              if (find.text('核对参考答案与关键点').evaluate().isNotEmpty) {
                await tap(find.text(wrong ? '有遗漏 / 答错' : '关键点正确'));
              }
              await drain(4);
              await screenshot('practice_answer_${i + 1}');
              if (i + 1 < list.length && i < 4) await tap(find.text('下一题'));
            }
            final submissions = await tester.runAsync(
              () => db.query('practice_submissions'),
            );
            report['submissions'] = submissions!.length;
            expect(submissions.length, greaterThanOrEqualTo(5));
            final wrongs = await tester.runAsync(
              () => db.query('practice_questions', where: 'wrong_count>0'),
            );
            expect(wrongs, isNotEmpty);
          });
          await step('一键生成知识卡片、提纲、导图和练习', () async {
            await mount(AiGenerationPage(documentId: document));
            await waitFor(
              () => find.text('一键生成全部').evaluate().isNotEmpty,
              'AI generation page',
            );
            await tap(find.text('一键生成全部'));
            final watch = Stopwatch()..start();
            List<Map<String, Object?>> jobs = [];
            while (watch.elapsed.inSeconds < 280) {
              await drain(5);
              jobs =
                  (await tester.runAsync(
                    () => db.query(
                      'ai_generation_tasks',
                      where: 'document_id=?',
                      whereArgs: [document],
                    ),
                  )) ??
                  [];
              if (jobs.length >= 4 &&
                  jobs.every(
                    (j) =>
                        j['status'] == 'completed' || j['status'] == 'failed',
                  )) {
                break;
              }
            }
            report['generationTasks'] = jobs
                .map(
                  (j) => {
                    'type': j['task_type'],
                    'status': j['status'],
                    'error': j['error_message'],
                  },
                )
                .toList();
            expect(
              jobs.map((j) => j['task_type']).toSet(),
              containsAll([
                'knowledge_cards',
                'review_outline',
                'mindmap_text',
                'practice_questions',
              ]),
            );
            expect(jobs.every((j) => j['status'] == 'completed'), isTrue);
            await screenshot('ai_results');
          });
        }
        await step('专注开始、暂停、继续、结束与打卡', () async {
          await mount(const FocusTabPage());
          await waitFor(
            () => find.text('开始专注').evaluate().isNotEmpty,
            'focus ready',
          );
          await tap(find.text('开始专注'));
          await drain(12);
          await tap(find.text('暂停'));
          await tap(find.text('继续'));
          await drain(8);
          await tap(find.text('结束'));
          await drain(5);
          if (find.text('打卡').evaluate().isNotEmpty) await tap(find.text('打卡'));
          final records = await tester.runAsync(
            () => db.query(
              'pomodoro_records',
              where: 'user_id=?',
              whereArgs: [localIds['zdd']],
            ),
          );
          expect(records, isNotEmpty);
          await screenshot('focus_completed');
        });
        if (userA != null && userB != null) {
          await step('zdd 界面发送好友申请', () async {
            await mount(CommunityUserPage(userId: userA!));
            await waitFor(
              () =>
                  find.text('添加好友').evaluate().isNotEmpty ||
                  find.text('已发送申请').evaluate().isNotEmpty ||
                  find.text('发消息').evaluate().isNotEmpty,
              'peer profile',
            );
            if (find.text('添加好友').evaluate().isNotEmpty) {
              await tap(find.text('添加好友'));
            }
            final status = await tester.runAsync(
              () => repo.friendStatus(userA!),
            );
            expect(['sent', 'friend'], contains(status));
            await screenshot('friend_request');
          });
          await step('yk 登录并采纳真实回答', () async {
            await login('yk', 'A');
            await mount(QuestionDetailPage(questionId: ids.first));
            await waitFor(
              () => find.text(questions.first.title).evaluate().isNotEmpty,
              'question rendered',
            );
            await tap(find.text('采纳'));
            final q = await tester.runAsync(() => repo.question(ids.first));
            expect(q!['accepted_answer_id'], isNotNull);
            await screenshot('accepted_final');
          });
          await step('yk 界面同意好友申请', () async {
            if (await tester.runAsync(() => repo.friendStatus(userB!)) !=
                'friend') {
              await mount(const FriendsChatPage(initialIndex: 2));
              await waitFor(
                () => find.text('同意').evaluate().isNotEmpty,
                'incoming friend request',
              );
              await tap(find.text('同意'));
            }
            expect(
              await tester.runAsync(() => repo.friendStatus(userB!)),
              'friend',
            );
            conversation = await tester.runAsync(
              () => repo.openConversation(userB!),
            );
            report['conversation'] = conversation;
          });
          if (conversation != null) {
            await step('yk 真实聊天界面发送消息', () async {
              await mount(ChatPage(conversationId: conversation!));
              await waitFor(
                () => find.byType(TextField).evaluate().isNotEmpty,
                'chat ready',
              );
              await tester.enterText(
                find.byType(TextField),
                '【联调测试】已看过你的最短路径解答，一起复习负环检测和数据库索引。',
              );
              await tap(find.text('发送'));
              await drain(10);
              final messages = await tester.runAsync(
                () => repo.messages(conversation!),
              );
              expect(messages!.any((m) => m['sender_id'] == userA), isTrue);
              await screenshot('chat_sent');
            });
            await step('zdd 接收并回复真实私聊消息', () async {
              await login('zdd', 'B');
              await mount(ChatPage(conversationId: conversation!));
              await waitFor(
                () => find.textContaining('已看过你的最短路径解答').evaluate().isNotEmpty,
                'message received',
              );
              await tester.enterText(
                find.byType(TextField),
                '【联调测试】收到，我已整理知识库并完成练习，接下来回顾错题。',
              );
              await tap(find.text('发送'));
              await drain(10);
              final messages = await tester.runAsync(
                () => repo.messages(conversation!),
              );
              expect(messages!.any((m) => m['sender_id'] == userB), isTrue);
              await screenshot('chat_reply');
            });
          }
        }
        await finish();
        return;
      }
      await step('yk 通过真实登录页面登录并恢复会话', () => login('yk', 'A'));
      if (userA != null) {
        await step('yk 界面创建知识库与学习任务', () => createLibraryAndTask('yk'));
        await step('yk GLM 模型连接与配置保存', () => configureModel('yk'));
        for (var i = 0; i < questions.length; i++) {
          await step('yk 界面发布专业问题 ${i + 1}', () async {
            final q = questions[i];
            final existing = await tester.runAsync(
              () => client
                  .from('community_questions')
                  .select('id')
                  .eq('author_id', userA!)
                  .eq('title', q.title),
            );
            if (existing!.isNotEmpty) {
              ids.add(existing.first['id'] as String);
              report['questions'] = ids.toList();
              return;
            }
            await mount(const PublishQuestionPage());
            await tester.enterText(field('问题标题'), q.title);
            await tester.enterText(field('问题描述'), q.body);
            await reveal(field('知识标签'));
            await tester.enterText(field('知识标签'), q.tags);
            await tap(find.widgetWithText(FilledButton, '发布问题'));
            await waitFor(
              () => find.byType(QuestionDetailPage).evaluate().isNotEmpty,
              'published question detail',
            );
            final page = tester.widget<QuestionDetailPage>(
              find.byType(QuestionDetailPage),
            );
            ids.add(page.questionId);
            report['questions'] = ids.toList();
            await writeReport();
            final remote = await tester.runAsync(
              () => repo.question(page.questionId),
            );
            expect(remote!['title'], q.title);
            await waitFor(
              () => find.text(q.title).evaluate().isNotEmpty,
              'remote question rendered',
            );
            await screenshot('question_${i + 1}');
          });
        }
      }
      await step('zdd 切换账号并通过真实登录页面登录', () => login('zdd', 'B'));
      if (userB != null) {
        await step('zdd 界面创建知识库与学习任务', () => createLibraryAndTask('zdd'));
        await step('zdd GLM 模型连接与配置保存', () => configureModel('zdd'));
        for (var i = 0; i < ids.length; i++) {
          await step('zdd 界面回答并收藏专业问题 ${i + 1}', () async {
            await mount(QuestionDetailPage(questionId: ids[i]));
            await waitFor(
              () => find.text(questions[i].title).evaluate().isNotEmpty,
              'question loaded as zdd',
            );
            await tap(find.text('收藏'));
            await waitFor(
              () => find.text('已收藏').evaluate().isNotEmpty,
              'bookmark persisted',
            );
            await reveal(field('写下你的回答'));
            await tester.enterText(field('写下你的回答'), questions[i].answer);
            await tap(find.text('发布回答'));
            await drain(10);
            final answers = await tester.runAsync(() => repo.answers(ids[i]));
            expect(
              answers!.any(
                (a) =>
                    a['author_id'] == userB && a['body'] == questions[i].answer,
              ),
              isTrue,
            );
            await screenshot('answered_${i + 1}');
          });
        }
        if (ids.isNotEmpty && libraryIds['zdd'] != null) {
          await step('zdd 社区内容存入个人知识库', () async {
            await mount(QuestionDetailPage(questionId: ids.first));
            await waitFor(
              () => find.text('存入知识库').evaluate().isNotEmpty,
              'save community content',
            );
            await tap(find.text('存入知识库').first);
            await waitFor(
              () => find.text('保存到我的知识库').evaluate().isNotEmpty,
              'choose destination',
            );
            await tap(find.text('zdd · 计算机专业学习'));
            await drain(10);
            final sources = await tester.runAsync(
              () => db.query(
                'source_documents',
                where: 'user_id=?',
                whereArgs: [localIds['zdd']],
              ),
            );
            expect(sources, isNotEmpty);
            report['savedSourceDocuments'] = sources!
                .map((s) => s['id'])
                .toList();
            await screenshot('saved_to_library');
          });
        }
        if (libraryIds['zdd'] != null) {
          await step('zdd 真实 GLM 生成练习题', () async {
            await mount(LibraryPracticePage(libraryId: libraryIds['zdd']));
            await waitFor(
              () => find.text('练习范围').evaluate().isNotEmpty,
              'practice page',
            );
            await screenshot('practice_before');
            // Locate the explicit generation button by its rendered label.
            final labels = tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .whereType<String>()
                .where((s) => s.contains('生成'))
                .toList();
            report['practiceGenerationLabels'] = labels;
            await writeReport();
            await tap(find.text('基于所选范围组卷'));
            final watch = Stopwatch()..start();
            List<Map<String, Object?>> rows = [];
            while (rows.isEmpty && watch.elapsed.inSeconds < 140) {
              await drain(3);
              rows =
                  (await tester.runAsync(
                    () => db.query('practice_questions'),
                  )) ??
                  [];
              if (find.textContaining('没有已解析资料').evaluate().isNotEmpty) {
                throw StateError('社区存入的资料未被组卷识别为已解析资料');
              }
            }
            expect(
              rows,
              isNotEmpty,
              reason: 'Real generated questions must be persisted',
            );
            report['generatedQuestions'] = rows.length;
            await screenshot('practice_generated');
          });
        }
        if (userA != null) {
          await step('zdd 界面向 yk 发送好友申请', () async {
            await mount(CommunityUserPage(userId: userA!));
            await waitFor(
              () =>
                  find.text('添加好友').evaluate().isNotEmpty ||
                  find.text('已发送申请').evaluate().isNotEmpty ||
                  find.text('发消息').evaluate().isNotEmpty,
              'user profile',
            );
            if (find.text('添加好友').evaluate().isNotEmpty) {
              await tap(find.text('添加好友'));
            }
            final status = await tester.runAsync(
              () => repo.friendStatus(userA!),
            );
            expect(['sent', 'friend'], contains(status));
            await screenshot('friend_request');
          });
        }
      }
      if (userA != null && userB != null) {
        await step('yk 再次登录且本地知识库隔离', () async {
          await login('yk', 'A');
          final libs = await tester.runAsync(
            () => KnowledgeLibraryRepository().fetchLibraries(localIds['yk']!),
          );
          expect(libs!.any((l) => l.name.startsWith('zdd')), isFalse);
        });
        if (ids.isNotEmpty) {
          await step('yk 界面采纳回答并检查通知', () async {
            await mount(QuestionDetailPage(questionId: ids.first));
            await waitFor(
              () => find.text(questions.first.title).evaluate().isNotEmpty,
              'answer available',
            );
            await tap(find.text('采纳'));
            final q = await tester.runAsync(() => repo.question(ids.first));
            expect(q!['accepted_answer_id'], isNotNull);
            final notifications = await tester.runAsync(
              () => repo.notifications(),
            );
            expect(
              notifications!.any(
                (n) => n['kind'] == 'answer' && n['question_id'] == ids.first,
              ),
              isTrue,
            );
            await screenshot('answer_accepted');
          });
        }
        await step('yk 界面接受好友申请', () async {
          await mount(const FriendsChatPage(initialIndex: 2));
          await waitFor(
            () =>
                find.text('同意').evaluate().isNotEmpty ||
                find.text('接受').evaluate().isNotEmpty,
            'friend request action',
          );
          await tap(
            find.text(find.text('同意').evaluate().isNotEmpty ? '同意' : '接受'),
          );
          final status = await tester.runAsync(() => repo.friendStatus(userB!));
          expect(status, 'friend');
          conversation = await tester.runAsync(
            () => repo.openConversation(userB!),
          );
          report['conversation'] = conversation;
          await screenshot('friends');
        });
        if (conversation != null) {
          await step('yk 界面发送私聊消息', () async {
            await mount(ChatPage(conversationId: conversation!));
            await waitFor(
              () => find.byType(TextField).evaluate().isNotEmpty,
              'chat ready',
            );
            await tester.enterText(
              find.byType(TextField),
              '【联调测试】我已看过你的最短路径解答。接下来一起复习负环检测和复合索引，练习后交流错题。',
            );
            await tap(find.text('发送'));
            await drain(10);
            final messages = await tester.runAsync(
              () => repo.messages(conversation!),
            );
            expect(messages!.any((m) => m['sender_id'] == userA), isTrue);
            await screenshot('chat_sent');
          });
        }
        if (conversation != null) {
          await step('zdd 接收并回复私聊消息', () async {
            await login('zdd', 'B');
            await mount(ChatPage(conversationId: conversation!));
            await waitFor(
              () => find.textContaining('我已看过你的最短路径解答').evaluate().isNotEmpty,
              'peer message rendered',
            );
            await tester.enterText(
              find.byType(TextField),
              '【联调测试】收到。我会把算法原理整理进知识库，再完成一组练习。',
            );
            await tap(find.text('发送'));
            await drain(10);
            final messages = await tester.runAsync(
              () => repo.messages(conversation!),
            );
            expect(messages!.any((m) => m['sender_id'] == userB), isTrue);
            await screenshot('chat_reply');
          });
        }
      }
      await finish();
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
