import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/favorite_repository.dart';
import 'package:pxt1/ui/theme/app_theme.dart';
import 'package:pxt1/ui/widgets/favorite_annotation_sheet.dart';

const _body = 'alpha beta alpha gamma\nsecond line.';
const _capturePreviews = bool.fromEnvironment('UPDATE_FAVORITE_SCREENSHOTS');
final _capture = GlobalKey();

class _Store {
  String body = _body;
  List<FavoriteAnnotation> annotations = [];
  bool fail = false;
  Future<void> save(List<FavoriteAnnotation> next) async {
    if (fail) throw StateError('测试存储失败');
    annotations = [...next];
  }
}

void main() {
  setUpAll(() async {
    if (!_capturePreviews) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('FavoritePreviewChinese')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
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
  Future<void> open(
    WidgetTester tester,
    _Store store, {
    double width = 390,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _capturePreviews
              ? AppTheme.light.copyWith(
                  shadowColor: Colors.transparent,
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(
                        fontFamily: 'FavoritePreviewChinese',
                      ),
                    ),
                  ),
                  textTheme: AppTheme.light.textTheme.apply(
                    fontFamily: 'FavoritePreviewChinese',
                  ),
                )
              : AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('打开收藏'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => FavoriteAnnotationSheet(
                    item: FavoriteItemRecord(
                      favoriteId: 9,
                      targetType: FavoriteTargetType.reviewOutline,
                      targetId: 11,
                      title: '函数复习',
                      subtitle: '高数资料 / 复习提纲',
                      body: store.body,
                      createdAt: DateTime(2026),
                      annotations: store.annotations,
                    ),
                    onSave: store.save,
                    onClearLegacyNote: () async {},
                    onClearLegacyHighlight: () async {},
                    onRemoveFavorite: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
  }

  EditableTextState editable(WidgetTester tester) =>
      tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const ValueKey('favorite-annotated-body')),
          matching: find.byType(EditableText),
        ),
      );
  Future<void> select(WidgetTester tester, int start, int end) async {
    final state = editable(tester);
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection(baseOffset: start, extentOffset: end),
      ),
      SelectionChangedCause.longPress,
    );
    await tester.pump();
  }

  List<TextSpan> highlights(WidgetTester tester) => tester
      .widget<SelectableText>(
        find.byKey(const ValueKey('favorite-annotated-body')),
      )
      .textSpan!
      .children!
      .whereType<TextSpan>()
      .where((span) => span.style?.backgroundColor != null)
      .toList();
  Future<void> reopen(WidgetTester tester) async {
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
  }

  testWidgets('selection colors only its occurrence and survives reopening', (
    tester,
  ) async {
    final store = _Store();
    await open(tester, store);
    expect(editable(tester).textEditingValue.text, _body);
    expect(find.byType(TextField), findsNothing);
    expect(
      tester
          .widgetList<IconButton>(find.byType(IconButton))
          .firstWhere((button) => button.tooltip == '黄色高亮')
          .onPressed,
      isNull,
    );
    await select(tester, 11, 16);
    await tester.tap(find.byTooltip('黄色高亮'));
    await tester.pumpAndSettle();
    expect(store.annotations.single.start, 11);
    expect(store.annotations.single.quote, 'alpha');
    expect(store.annotations.single.color, '黄色');
    expect(highlights(tester).single.text, 'alpha');
    await reopen(tester);
    expect(highlights(tester).single.text, 'alpha');
    expect(find.text('高亮重点'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('note tag toggles popup; editing and deleting retain highlight', (
    tester,
  ) async {
    final store = _Store();
    await open(tester, store);
    await select(tester, 11, 16);
    await tester.tap(find.byTooltip('绿色高亮'));
    await tester.pumpAndSettle();
    await select(tester, 11, 16);
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    expect(find.text('“alpha”'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '理解这段推导');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final id = store.annotations.single.id;
    expect(store.annotations.single.note, '理解这段推导');
    expect(find.text('理解这段推导'), findsNothing);
    final tag = find.byKey(ValueKey('note-tag-$id'));
    await tester.tap(tag);
    await tester.pumpAndSettle();
    expect(find.text('理解这段推导'), findsOneWidget);
    await tester.tap(tag);
    await tester.pumpAndSettle();
    expect(find.text('理解这段推导'), findsNothing);
    await reopen(tester);
    await tester.tap(tag);
    await tester.pumpAndSettle();
    expect(find.text('理解这段推导'), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '修改后的笔记');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(tag);
    await tester.pumpAndSettle();
    expect(find.text('修改后的笔记'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(store.annotations.single.note, isNull);
    expect(store.annotations.single.color, '绿色');
    expect(tag, findsNothing);
    expect(highlights(tester), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real long press selects original text; failed saves can retry at 320px',
    (tester) async {
      final store = _Store()..fail = true;
      await open(tester, store, width: 320);
      final render = editable(tester).renderEditable;
      final caret = render.getLocalRectForCaret(const TextPosition(offset: 13));
      await tester.longPressAt(render.localToGlobal(caret.center));
      await tester.pumpAndSettle();
      expect(
        editable(tester).textEditingValue.selection.textInside(_body),
        'alpha',
      );
      editable(tester).hideToolbar();
      await tester.pump();
      await tester.tap(find.byTooltip('蓝色高亮'));
      await tester.pumpAndSettle();
      expect(store.annotations, isEmpty);
      expect(highlights(tester), isEmpty);
      expect(find.textContaining('批注保存失败'), findsOneWidget);
      store.fail = false;
      await select(tester, 11, 16);
      await tester.tap(find.byTooltip('蓝色高亮'));
      await tester.pumpAndSettle();
      expect(store.annotations.single.color, '蓝色');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clearing part of a highlight leaves outside text and note intact',
    (tester) async {
      final store = _Store()
        ..annotations = [
          const FavoriteAnnotation(
            id: 'note',
            start: 0,
            end: 16,
            quote: 'alpha beta alpha',
            color: '黄色',
            note: '不删笔记',
          ),
        ];
      await open(tester, store);
      await select(tester, 6, 10);
      await tester.tap(find.byTooltip('取消所选高亮'));
      await tester.pumpAndSettle();
      expect(
        store.annotations.where((a) => a.note != null).single.note,
        '不删笔记',
      );
      expect(
        store.annotations.where((a) => a.color != null).map((a) => a.quote),
        ['alpha ', ' alpha'],
      );
      expect(find.byKey(const ValueKey('note-tag-note')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'capture selected text highlights and toggleable note preview',
    (tester) async {
      final store = _Store()
        ..body =
            '一、判断函数的单调性\n\n先求函数的导数，再判断导数的符号。\n\n当导数大于零时，函数在该区间单调递增；当导数小于零时，函数在该区间单调递减。\n\n二、容易忽略的条件\n\n讨论单调性前，先确定定义域。遇到分段函数时，需要分别讨论每个区间。';
      final start = store.body.indexOf('先求函数的导数');
      final end = store.body.indexOf('。', start) + 1;
      store.annotations = [
        FavoriteAnnotation(
          id: 'preview',
          start: start,
          end: end,
          quote: store.body.substring(start, end),
          color: '黄色',
          note: '先确定定义域，再求导。判断的是整个区间内的导数符号，不能只看某一个点。',
        ),
        FavoriteAnnotation(
          id: 'preview-second',
          start: store.body.indexOf('讨论单调性前'),
          end: store.body.length,
          quote: store.body.substring(store.body.indexOf('讨论单调性前')),
          note: '先检查定义域，再逐段讨论。',
        ),
      ];
      await open(tester, store);
      final render = editable(tester).renderEditable;
      for (final annotation in store.annotations) {
        final boxes = render.getBoxesForSelection(
          TextSelection(
            baseOffset: annotation.start,
            extentOffset: annotation.end,
          ),
        );
        final expectedTop = render.localToGlobal(Offset(0, boxes.last.top)).dy;
        final actualTop = tester
            .getTopLeft(find.byKey(ValueKey('note-tag-${annotation.id}')))
            .dy;
        expect(actualTop, closeTo(expectedTop, 2));
      }
      expect(
        tester
            .getRect(find.byKey(const ValueKey('favorite-annotated-body')))
            .bottom,
        lessThanOrEqualTo(
          tester
              .getRect(find.byKey(const ValueKey('favorite-annotation-layout')))
              .bottom,
        ),
      );
      Future<void> capture(String name) async {
        final boundary =
            _capture.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/favorite-validation').create(recursive: true);
          await File(
            'docs/favorite-validation/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('highlight-with-note-tag');
      await tester.tap(find.byKey(const ValueKey('note-tag-preview')));
      await tester.pumpAndSettle();
      await capture('note-expanded');
      expect(find.text(store.annotations.first.note!), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !_capturePreviews,
  );
}
