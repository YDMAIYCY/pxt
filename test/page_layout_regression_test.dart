import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/ui/pages/tabs/profile_tab_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

void main() {
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

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('保存 AI 配置'), findsOneWidget);
  });
}
