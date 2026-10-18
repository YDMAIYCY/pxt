// Run explicitly: flutter test --no-pub test/_library_practice_preview.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/ui/pages/library_practice_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

ThemeData _previewTheme() {
  final base = AppTheme.light;
  TextStyle font(TextStyle? style) =>
      (style ?? const TextStyle()).copyWith(fontFamily: 'Microsoft YaHei');
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Microsoft YaHei'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: font(base.appBarTheme.titleTextStyle),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: font(base.chipTheme.labelStyle),
      secondaryLabelStyle: font(base.chipTheme.secondaryLabelStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          font(base.filledButtonTheme.style?.textStyle?.resolve({})),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;

  setUpAll(() async {
    final font = File(r'C:\Windows\Fonts\msyh.ttc');
    if (font.existsSync()) {
      final bytes = await font.readAsBytes();
      final data = ByteData.sublistView(bytes);
      for (final family in [
        'Microsoft YaHei',
        'Roboto',
        'Ahem',
        'sans-serif',
      ]) {
        await (FontLoader(family)..addFont(Future.value(data))).load();
      }
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('users', {
      'id': 1,
      'username': 'preview',
      'password_hash': 'test',
      'password_salt': 'test',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('auth_sessions', {
      'user_id': 1,
      'session_token': 'preview',
      'created_at': now,
    });
    for (final id in [1, 2]) {
      await db.insert('knowledge_libraries', {
        'id': id,
        'user_id': 1,
        'name': id == 1 ? '数据结构' : '计算机网络与分布式系统课程笔记',
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.insert('import_records', {
      'id': 1,
      'user_id': 1,
      'library_id': 1,
      'operation_id': 'preview-record',
      'title': '第三章：栈、队列与递归的课堂笔记',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('source_documents', {
      'id': 1,
      'user_id': 1,
      'library_id': 1,
      'import_record_id': 1,
      'source_type': 'gallery_import',
      'image_path': '',
      'original_title': '第三章课堂笔记',
      'created_at': now,
    });
    await db.insert('knowledge_concepts', {
      'id': 1,
      'user_id': 1,
      'library_id': 1,
      'document_id': 1,
      'name': '栈与队列在递归和广度优先搜索中的应用',
      'summary': '栈后进先出，队列先进先出。',
      'evidence_text': '课堂笔记',
      'mastery_score': 40,
      'weakness_score': 60,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('practice_questions', {
      'id': 1,
      'document_id': 1,
      'question_text': '栈和队列的区别是什么？',
      'answer_text': '后进先出与先进先出',
      'review_status': 'pending',
      'created_at': now,
    });
    await db.insert('question_concepts', {'question_id': 1, 'concept_id': 1});
  });
  tearDown(() async => db.close());

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final (width, scale) in [(360.0, 1.3), (390.0, 1.0), (430.0, 1.0)]) {
    testWidgets('practice fits ${width}dp at scale $scale in both modes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _previewTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: LibraryPracticePage(
              initialQuestionId: 1,
              documentId: 1,
              recordId: 1,
              initialConceptId: 1,
              database: app,
            ),
          ),
        ),
      );
      await flush(tester);
      for (final generate in [false, true]) {
        if (generate) {
          await tester.tap(find.text('AI 出新题'));
          await tester.pumpAndSettle();
        }
        final action = find.text(generate ? '生成 5 道题并练习' : '开始练习');
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width == 390) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = Directory('docs/ui-design-20261018');
            await output.create(recursive: true);
            await File(
              '${output.path}/practice-${generate ? 'generate' : 'existing'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    });
  }
}
