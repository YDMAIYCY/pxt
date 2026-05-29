import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/game/games/game_2048_page.dart';
import 'package:pxt1/game/games/idiom_game_page.dart';
import 'package:pxt1/game/games/minesweeper_game_page.dart';
import 'package:pxt1/game/games/slide_puzzle_game_page.dart';
import 'package:pxt1/ui/pages/tabs/profile_tab_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

void main() {
  testWidgets('2048 page lays out the board and can be popped', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Game2048Page(),
                    ),
                  );
                },
                child: const Text('打开 2048'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开 2048'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('滑动合并数字'), findsOneWidget);
    expect(find.text('新游戏'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('打开 2048'), findsOneWidget);
  });

  testWidgets('LLM config page lays out editable controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LlmConfigEditPage(config: LlmProviderConfig.emptyForUser(7)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('通用大模型'), findsOneWidget);
    expect(find.text('服务商名称'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('Base URL'), findsOneWidget);
    expect(find.text('保存 AI 配置'), findsOneWidget);
  });

  testWidgets('other game boards avoid narrow-phone overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final pages = <String, Widget>{
      '成语寻踪': const IdiomGamePage(),
      '扫雷挑战': const MinesweeperGamePage(),
      '数字华容道': const SlidePuzzleGamePage(),
    };

    for (final entry in pages.entries) {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: entry.value),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '${entry.key} overflowed');
      expect(find.text(entry.key), findsOneWidget);
    }
  });
}
