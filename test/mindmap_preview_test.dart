import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/ui/theme/app_theme.dart';
import 'package:pxt1/ui/widgets/record_mindmap_view.dart';

const _capturePreviews = bool.fromEnvironment('UPDATE_MINDMAP_SCREENSHOTS');
const _map =
    '数据结构与算法\n- 复杂度分析\n  - 时间复杂度\n    - O(1) 常数时间\n    - O(log n) 对数时间\n  - 空间复杂度\n    - 额外存储开销\n- 线性结构\n  - 数组与链表\n  - 栈与队列\n- 树与图\n  - 二叉树遍历\n  - 图的搜索\n- 查找与排序\n  - 二分查找\n  - 快速排序\n- 哈希表\n  - 哈希函数\n  - 冲突处理\n- 学习与实践\n  - 比较适用场景\n  - 分析边界条件';

void main() {
  setUpAll(() async {
    if (!_capturePreviews) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      for (final family in ['MindmapPreviewChinese', 'Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
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
  testWidgets(
    'capture spread layout, full screen portrait/landscape and search colors',
    (tester) async {
      final captureKey = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light.copyWith(
              appBarTheme: AppTheme.light.appBarTheme.copyWith(
                titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle!
                    .copyWith(fontFamily: 'MindmapPreviewChinese'),
              ),
              textButtonTheme: TextButtonThemeData(
                style: AppTheme.light.textButtonTheme.style!.copyWith(
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(
                      fontFamily: 'MindmapPreviewChinese',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              textTheme: AppTheme.light.textTheme.apply(
                fontFamily: 'MindmapPreviewChinese',
              ),
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('思维导图')),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: RecordMindmapView(text: _map, onSource: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        final boundary =
            captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/mindmap-validation').create(recursive: true);
          await File(
            'docs/mindmap-validation/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('preview');
      await tester.tap(find.text('全屏'));
      await tester.pumpAndSettle();
      await capture('fullscreen-portrait');
      tester.view.physicalSize = const Size(1100, 700);
      await tester.pumpAndSettle();
      await capture('fullscreen-landscape');
      await tester.enterText(find.byType(TextField), '复杂度');
      await tester.pumpAndSettle();
      await capture('search-in-place');
      expect(find.byType(ListTile), findsNothing);
      expect(
        find.byKey(const ValueKey('mindmap-fullscreen-canvas')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !_capturePreviews,
  );
}
