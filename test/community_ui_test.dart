import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/community/cloud_backend.dart';
import 'package:pxt1/community/community_repository.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/focus/repository/focus_repository.dart';
import 'package:pxt1/ui/pages/community/community_page.dart';
import 'package:pxt1/ui/pages/tabs/profile_tab_page.dart';
import 'package:pxt1/ui/pages/tabs/focus_tab_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

// Only test fixtures use synthetic community responses; production has no seed data.
class FixtureCommunity extends CommunityRepository {
  final calls = <String>[];
  bool fail = false, empty = false;
  @override
  Future<List<Json>> feed({
    String mode = 'latest',
    String keyword = '',
    int offset = 0,
    String? author,
    bool bookmarks = false,
  }) async {
    calls.add('$mode:$keyword:$offset');
    if (fail) throw const CloudFailure('网络已断开');
    if (empty || mode == 'unanswered') return [];
    return List.generate(
      offset == 0 ? 20 : 1,
      (i) => {
        'id': 'fixture-${offset + i}',
        'author_id': 'fixture-author',
        'title': i == 0 && offset == 0 ? '如何理解微积分中的极限？' : '测试问题 ${offset + i}',
        'body': '学习中遇到一点困惑，想听听大家的思路。',
        'created_at': DateTime.now()
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
        'profile': {'id': 'fixture-author', 'nickname': '测试同学'},
        'tags': ['高等数学'],
        'image_paths': [],
        'accepted_answer_id': null,
        'answer_count': 0,
        'bookmark_count': 0,
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      final loader = FontLoader('CommunityTestChinese')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      final fallback = FontLoader('Ahem')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await fallback.load();
      final roboto = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await roboto.load();
    }
    final icons = File(
      'D:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          ))
          .load();
    }
  });
  final capture = GlobalKey();
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    double height = 844,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light.copyWith(
            textTheme: AppTheme.light.textTheme.apply(
              fontFamily: 'CommunityTestChinese',
            ),
            primaryTextTheme: AppTheme.light.primaryTextTheme.apply(
              fontFamily: 'CommunityTestChinese',
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: AppTheme.light.filledButtonTheme.style?.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: 'CommunityTestChinese',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          home: Scaffold(body: child),
        ),
      ),
    );
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('UPDATE_COMMUNITY_SCREENSHOTS')) return;
    final boundary =
        capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('docs/community-validation').create(recursive: true);
      await File(
        'docs/community-validation/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('community has one publishing entry and only three top filters', (
    tester,
  ) async {
    final repo = FixtureCommunity();
    await pump(tester, CommunityPage(repository: repo));
    expect(find.text('发问题'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('最新'), findsOneWidget);
    expect(find.text('待解答'), findsWidgets);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'community-fixture');
    await tester.tap(find.text('最新'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'latest::0');
    await tester.tap(find.widgetWithText(ChoiceChip, '待解答'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'unanswered::0');
    expect(find.text('还没有相关问题'), findsOneWidget);
  });
  testWidgets('community errors provide retry without inventing posts', (
    tester,
  ) async {
    final repo = FixtureCommunity()..fail = true;
    await pump(tester, CommunityPage(repository: repo));
    expect(find.text('网络已断开'), findsOneWidget);
    expect(find.text('如何理解微积分中的极限？'), findsNothing);
    repo.fail = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('如何理解微积分中的极限？'), findsOneWidget);
  });
  testWidgets('question search passes the literal user query to repository', (
    tester,
  ) async {
    final repo = FixtureCommunity();
    await pump(tester, CommunityPage(repository: repo, search: true));
    await tester.enterText(find.byType(TextField), '极限_%');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'recommended:极限_%:0');
    expect(tester.takeException(), isNull);
  });
  testWidgets('pagination loads the next page and keeps the first results', (
    tester,
  ) async {
    final repo = FixtureCommunity();
    await pump(tester, CommunityPage(repository: repo));
    for (var i = 0; i < 12 && !repo.calls.any((c) => c.endsWith(':20')); i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
    }
    expect(repo.calls.any((c) => c.endsWith(':20')), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'profile uses local focus records, keeps settings and opens original focus page',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('pxt-profile-ui-');
        final app = await AppDatabase.openForTesting(
          databaseFactoryFfi,
          path: '${dir.path}/profile.db',
        );
        final db = await app.database;
        final auth = AuthRepository(database: app);
        await auth.register(
          username: 'profile-fixture',
          password: 'local-fixture',
        );
        await auth.login(
          username: 'profile-fixture',
          password: 'local-fixture',
        );
        final user = (await auth.getCurrentUserProfile())!;
        await auth.saveUserProfile(
          user.copyWith(displayName: '测试同学', bio: '记录学习灵感，慢慢长成自己的知识库。'),
        );
        final today = DateTime.now();
        final date =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        await db.insert('checkin_records', {
          'user_id': user.id,
          'date': date,
          'study_seconds': 1800,
          'pomodoro_count': 1,
          'points_earned': 30,
          'is_makeup': 0,
          'created_at': today.toUtc().toIso8601String(),
        });
        return (app: app, db: db, dir: dir, auth: auth);
      }))!;
      final app = fixture.app;
      final db = fixture.db;
      final dir = fixture.dir;
      final auth = fixture.auth;
      await pump(
        tester,
        ProfileTabPage(
          authRepository: auth,
          sourceDocumentRepository: SourceDocumentRepository(database: app),
          llmConfigRepository: LlmConfigRepository(database: app),
          aiGenerationRepository: AiGenerationRepository(database: app),
          focusRepository: FocusRepository(database: app),
        ),
        width: 390,
        height: 1080,
      );
      expect(find.text('我的学习空间'), findsOneWidget);
      expect(find.text('0.5'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'profile-local-fixture');
      await tester.scrollUntilVisible(
        find.text('专注学习'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('专注学习'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusTabPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
    },
  );
  testWidgets('community remains usable at 320 logical pixels', (tester) async {
    await pump(
      tester,
      CommunityPage(repository: FixtureCommunity()),
      width: 320,
      height: 740,
    );
    expect(tester.takeException(), isNull);
  });
}
