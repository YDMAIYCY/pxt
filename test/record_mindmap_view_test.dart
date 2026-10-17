import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/ui/theme/app_theme.dart';
import 'package:pxt1/ui/widgets/record_mindmap_view.dart';

const mapText =
    'Data structures\n- Storage\n  - Hash table\n  - Hash collisions\n- Algorithms\n  - Binary search\n  - Sorting\n- Complexity\n  - O(n log n)\n  - Memory usage';

void main() {
  Future<void> show(
    WidgetTester tester, {
    double width = 390,
    VoidCallback? onSource,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RecordMindmapView(
                text: mapText,
                onSource: onSource ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'canvas tap opens full screen; drag and zoom remain usable and source is available',
    (tester) async {
      var sources = 0;
      await show(tester, onSource: () => sources++);
      await tester.tap(find.byKey(const ValueKey('mindmap-preview-canvas')));
      await tester.pumpAndSettle();
      final canvas = find.byKey(const ValueKey('mindmap-fullscreen-canvas'));
      expect(canvas, findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      final controller = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final scale = controller.value.getMaxScaleOnAxis();
      expect(scale, greaterThanOrEqualTo(0.65));
      await tester.tap(find.byTooltip('放大导图'));
      await tester.pumpAndSettle();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(scale));
      final before = controller.value.clone();
      await tester.drag(canvas, const Offset(-70, 30));
      await tester.pumpAndSettle();
      expect(controller.value, isNot(before));
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mindmap-preview-canvas')),
        findsOneWidget,
      );
      await tester.tap(find.text('全屏'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看原始资料'));
      await tester.pumpAndSettle();
      expect(sources, 1);
      expect(
        find.byKey(const ValueKey('mindmap-preview-canvas')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full screen uses root navigator and covers the home bottom dock',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => SingleChildScrollView(
                        child: RecordMindmapView(
                          text: mapText,
                          onSource: () {},
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 64, child: Text('首页底部导航')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('首页底部导航'), findsOneWidget);
      await tester.tap(find.text('全屏'));
      await tester.pumpAndSettle();
      expect(find.text('首页底部导航'), findsNothing);
      expect(
        find.byKey(const ValueKey('mindmap-fullscreen-canvas')),
        findsOneWidget,
      );
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('首页底部导航'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search reveals collapsed matches and marks text in place without a result list',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('全屏'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看全图'));
      await tester.pumpAndSettle();
      final branch = find.byKey(const ValueKey('mindmap-node-1'));
      await tester.tap(
        find.descendant(of: branch, matching: find.byTooltip('收起分支')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mindmap-node-2')), findsNothing);
      await tester.enterText(find.byType(TextField), 'hAsH');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mindmap-node-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('mindmap-node-5')), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('1/2 处匹配'), findsOneWidget);
      final title = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('mindmap-node-2')),
              matching: find.byType(Text),
            )
            .first,
      );
      final spans = (title.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .toList();
      expect(spans.first.text, 'Hash');
      expect(spans.first.style!.backgroundColor, const Color(0xFFFFD86B));
      final canvas = find.byKey(const ValueKey('mindmap-fullscreen-canvas'));
      final controller = tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final before = controller.value.clone();
      await tester.tap(find.byTooltip('下一处匹配'));
      await tester.pumpAndSettle();
      expect(find.text('2/2 处匹配'), findsOneWidget);
      expect(controller.value, isNot(before));
      await tester.enterText(find.byType(TextField), 'not present');
      await tester.pumpAndSettle();
      expect(find.text('未找到匹配节点'), findsOneWidget);
      expect(find.byKey(const ValueKey('mindmap-node-2')), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mindmap-node-9')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'different primary branches have distinct colors and 320px controls do not overflow',
    (tester) async {
      await show(tester, width: 320);
      Color? fill(int id) =>
          (tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: find.byKey(ValueKey('mindmap-node-$id')),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      expect({fill(1), fill(4), fill(7)}, hasLength(3));
      await tester.tap(find.text('全屏'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mindmap-fullscreen-canvas')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
