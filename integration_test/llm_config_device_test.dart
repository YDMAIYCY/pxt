import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/ui/pages/llm_config_edit_page.dart';
import 'package:sqflite/sqflite.dart';

// Run in an isolated applicationId (com.example.pxt1.llmcheck), never install
// an integration-test binary over the user's normal application.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android secure storage and provider configuration round trip', (
    tester,
  ) async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(storageNamespace: 'llm_device_acceptance'),
    );
    await storage.deleteAll();
    await storage.write(key: 'native_round_trip', value: 'device-fixture');
    expect(await storage.read(key: 'native_round_trip'), 'device-fixture');
    final app = await AppDatabase.openForTesting(databaseFactory);
    final db = await app.database;
    addTearDown(() async {
      await db.close();
      await storage.deleteAll();
    });
    await db.insert('users', {
      'id': -1014,
      'username': 'llm-device-check',
      'password_hash': 'fixture',
      'password_salt': 'fixture',
      'created_at': '2026-10-15',
      'updated_at': '2026-10-15',
    });
    final repository = LlmConfigRepository(
      database: app,
      secureStorage: storage,
    );
    final initial = LlmProviderConfig.emptyForUser(-1014);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final config = await repository.getByUserId(-1014) ?? initial;
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LlmConfigEditPage(
                        config: config,
                        repository: repository,
                      ),
                    ),
                  );
                },
                child: const Text('打开模型配置'),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.text('打开模型配置'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 100; i++) {
        if (find
                .byKey(const ValueKey('provider_openai'))
                .evaluate()
                .isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('provider_openai')), findsOneWidget);
    }

    Future<void> reveal(Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    Future<void> provider(String id) async {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final target = find.byKey(ValueKey('provider_$id'));
      await reveal(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> key(String value) async {
      final field = find.byKey(const ValueKey('field_API Key'));
      await reveal(field);
      await tester.enterText(field, value);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    await open();
    await provider('deepseek');
    await key('device-deepseek-fixture');
    await provider('opencode_go');
    await key('device-go-fixture');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 450 && find.text('打开模型配置').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('打开模型配置'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Text),
            ),
          )
          .map((widget) => widget.data)
          .join(' '),
    );
    expect((await repository.getByUserId(-1014))?.provider, 'opencode_go');
    expect(
      (await repository.getForProvider(-1014, 'deepseek'))?.apiKey,
      'device-deepseek-fixture',
    );
    await open();
    await reveal(find.byKey(const ValueKey('field_API Key')));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('field_API Key')))
          .controller!
          .text,
      'device-go-fixture',
    );
    await provider('deepseek');
    await reveal(find.byKey(const ValueKey('field_API Key')));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('field_API Key')))
          .controller!
          .text,
      'device-deepseek-fixture',
    );
    expect((await db.query('llm_provider_configs')).single['api_key'], '');
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('llm-config-device-top');
    await reveal(find.byType(ExpansionTile));
    await binding.takeScreenshot('llm-config-device-model');
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await reveal(find.text('测试连接'));
    await binding.takeScreenshot('llm-config-device-advanced');
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'secure_storage_round_trip': true,
      'independent_provider_profiles': true,
      'database_has_no_plaintext_key': true,
    });
    expect(tester.takeException(), isNull);
  });
}
