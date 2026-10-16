import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/ui/pages/learning_concept_page.dart';
import 'package:pxt1/ui/pages/library_practice_page.dart';
import 'package:pxt1/ui/pages/tabs/home_tab_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

/// 首页工作台的窄屏回归：真实数据下 320/360/390 宽都不得溢出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  final now = DateTime.now().toUtc();

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'student',
      'display_name': '同学',
      'password_hash': 't',
      'password_salt': 't',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('auth_sessions', {
      'user_id': 1,
      'session_token': 'fixture',
      'created_at': now.toIso8601String(),
    });

    final libraries = [
      (1, '软件设计模式', 'math', 0xFF5B90FF, 40, 68, 56),
      (2, '数据结构', 'network', 0xFF62BBA0, 30, 42, 32),
      (3, '计算机网络', 'building', 0xFFF2A37D, 25, 75, 28),
    ];
    var conceptId = 0;
    var questionId = 0;
    for (final (id, name, theme, color, concepts, mastery, questions)
        in libraries) {
      await db.insert('knowledge_libraries', {
        'id': id,
        'user_id': 1,
        'name': name,
        'cover_theme': theme,
        'cover_color': color,
        'created_at': now.toIso8601String(),
        'updated_at': now.subtract(Duration(days: id)).toIso8601String(),
      });
      await db.insert('source_documents', {
        'id': id,
        'user_id': 1,
        'library_id': id,
        'source_type': 'gallery_import',
        'image_path': '',
        'original_title': id == 1 ? '设计模式课堂笔记' : '$name 讲义',
        'created_at': now.subtract(Duration(hours: id * 5)).toIso8601String(),
      });
      for (var i = 0; i < concepts; i++) {
        conceptId++;
        await db.insert('knowledge_concepts', {
          'id': conceptId,
          'user_id': 1,
          'library_id': id,
          'document_id': id,
          'name': i == 0 && id == 1 ? '策略模式' : '$name 知识点 ${i + 1}',
          'summary': '核心概念说明。',
          'evidence_text': '证据原文。',
          'mastery_score': mastery,
          'weakness_score': 100 - mastery,
          'created_at': now.toIso8601String(),
          'updated_at': now.subtract(Duration(hours: i)).toIso8601String(),
        });
      }
      for (var i = 0; i < questions; i++) {
        questionId++;
        final wrong = id == 1 && i < 3;
        await db.insert('practice_questions', {
          'id': questionId,
          'document_id': id,
          'question_text': '$name 练习题 ${i + 1}',
          'answer_text': '参考答案',
          'review_status': wrong ? 'wrong' : 'pending',
          'wrong_count': wrong ? 2 : 0,
          'mastery_score': mastery,
          'next_review_at': now
              .add(Duration(days: i < 4 ? -2 : 3))
              .toIso8601String(),
          'created_at': now.toIso8601String(),
        });
      }
    }

    // 真实练习证据，推荐才带得出原因。
    for (final concept in [1, 41]) {
      final question = concept == 1 ? 1 : 60;
      await db.insert('question_concepts', {
        'question_id': question,
        'concept_id': concept,
      });
      await db.insert('practice_submissions', {
        'user_id': 1,
        'question_id': question,
        'request_id': 'req-$question',
        'answer': 'A',
        'correct': 0,
        'question_snapshot': '{}',
        'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      });
    }

    await db.insert('pomodoro_tasks', {
      'id': 1,
      'user_id': 1,
      'title': '完成设计模式练习',
      'kind': 'practice',
      'status': 'in_progress',
      'document_id': 1,
      'question_id': 1,
      'focused_seconds': 1800,
      'estimated_pomodoros': 2,
      'created_at': now.toIso8601String(),
    });
  });

  tearDown(() async => db.close());

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> render(WidgetTester tester, double width, {bool save = false}) async {
    await tester.binding.setSurfaceSize(Size(width, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: HomeTabPage(
              database: app,
              authRepository: AuthRepository(database: app),
              sourceDocumentRepository: SourceDocumentRepository(database: app),
              knowledgeLibraryRepository: KnowledgeLibraryRepository(
                database: app,
              ),
            ),
          ),
        ),
      ),
    );
    await flush(tester);
    expect(tester.takeException(), isNull);

    if (!save) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (!font.existsSync()) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.6);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/home_preview').create(recursive: true);
      await File(
        'build/home_preview/home_${width.round()}.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets('home workbench fits $width wide screens', (tester) async {
      await render(tester, width);
      expect(find.text('当前任务'), findsOneWidget);
      expect(find.text('学习概览'), findsOneWidget);
      expect(find.text('快捷操作'), findsOneWidget);
      expect(find.text('为你推荐'), findsOneWidget);
      expect(find.text('我的知识库'), findsOneWidget);
      expect(find.text('完成设计模式练习'), findsOneWidget);
      expect(find.text('继续学习'), findsOneWidget);
      expect(find.text('今日推荐'), findsOneWidget);
      expect(find.text('薄弱提升'), findsOneWidget);
    });
  }

  testWidgets('home workbench renders a preview image', (tester) async {
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await render(tester, 390, save: true);
  });

  testWidgets('home search reaches the user own concepts and opens them', (
    tester,
  ) async {
    await render(tester, 390);
    await tester.tap(find.byTooltip('搜索学习内容'));
    await tester.pumpAndSettle();
    expect(find.text('搜索学习内容'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '策略');
    await flush(tester);

    final hit = find.widgetWithText(ListTile, '策略模式');
    expect(hit, findsOneWidget);
    expect(find.text('知识点 · 软件设计模式'), findsOneWidget);

    await tester.tap(hit);
    await flush(tester);
    expect(find.byType(LearningConceptPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home reminders summarise the real backlog and jump to it', (
    tester,
  ) async {
    await render(tester, 390);
    await tester.tap(find.byTooltip('学习提醒'));
    await tester.pumpAndSettle();

    expect(find.text('学习提醒'), findsOneWidget);
    expect(find.text('待处理错题 3 道'), findsOneWidget);
    expect(find.text('复习到期 12 个'), findsOneWidget);
    expect(find.text('今日任务 13 项'), findsOneWidget);

    await tester.tap(find.text('待处理错题 3 道'));
    await flush(tester);
    final practice = tester.widget<LibraryPracticePage>(
      find.byType(LibraryPracticePage),
    );
    expect(practice.questionIds, isNotNull);
    expect(practice.questionIds, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
