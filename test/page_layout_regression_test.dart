import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/ui/pages/tabs/profile_tab_page.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> show(
    WidgetTester tester, {
    LlmProviderConfig? config,
    LlmConfigRepository? repository,
    http.Client? client,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: LlmConfigEditPage(
          config: config ?? LlmProviderConfig.emptyForUser(7),
          repository: repository,
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 360.0, 390.0, 600.0]) {
    testWidgets(
      'config page fits $width wide screens including expanded controls',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await show(tester, scale: width == 320 ? 1.3 : 1);
        expect(find.text('AI 模型配置'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('provider_siliconflow')),
          findsOneWidget,
        );
        expect(find.text('保存'), findsOneWidget);
        expect(find.text('测试连接'), findsNothing);
        await reveal(tester, find.byType(ExpansionTile));
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('测试连接'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'switching providers preserves independent keys, URLs and models',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(440, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final initial = LlmProviderConfig.emptyForUser(7).copyWith(
        provider: 'deepseek',
        apiKey: 'deepseek-secret',
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'deepseek-private',
      );
      await show(tester, config: initial);
      await tester.tap(find.byKey(const ValueKey('provider_opencode_go')));
      await tester.pumpAndSettle();
      TextField field(String label) =>
          tester.widget(find.byKey(ValueKey('field_$label')));
      expect(field('API Key').controller!.text, '');
      expect(
        field('Base URL').controller!.text,
        'https://opencode.ai/inference/go/v1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('field_API Key')),
        'go-secret',
      );
      await tester.enterText(
        find.byKey(const ValueKey('field_模型 ID')),
        'step-5-preview-free',
      );
      await tester.tap(find.byKey(const ValueKey('provider_deepseek')));
      await tester.pumpAndSettle();
      expect(field('API Key').controller!.text, 'deepseek-secret');
      expect(field('模型 ID').controller!.text, 'deepseek-private');
      await tester.tap(find.byTooltip('显示密钥'));
      await tester.pumpAndSettle();
      expect(field('API Key').obscureText, isFalse);
      await tester.tap(find.byKey(const ValueKey('provider_opencode_go')));
      await tester.pumpAndSettle();
      expect(field('API Key').controller!.text, 'go-secret');
      expect(field('API Key').obscureText, isTrue);
    },
  );

  testWidgets(
    'failed refresh allows manual entry and test errors stay accurate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(440, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response(
          '{"error":{"message":"invalid test-secret"}}',
          401,
        );
      });
      await show(
        tester,
        config: LlmProviderConfig.emptyForUser(7).copyWith(
          provider: 'opencode_go',
          apiMode: LlmApiMode.auto,
          apiKey: 'test-secret',
          baseUrl: 'https://opencode.ai/inference/go/v1',
          model: 'step-5-preview-free',
        ),
        client: client,
      );
      await tester.tap(find.text('刷新模型'));
      await tester.pumpAndSettle();
      expect(find.textContaining('可继续手动填写模型 ID'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('field_模型 ID')),
        'step-5-preview-free',
      );
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('测试连接'));
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.textContaining('连接失败：'), findsOneWidget);
      expect(find.textContaining('HTTP 401'), findsWidgets);
      expect(find.textContaining('连接成功 ·'), findsNothing);
      expect(find.textContaining('invalid test-secret'), findsNothing);
      expect(requests, 2);
    },
  );

  testWidgets('picker searches and selects with keyboard without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(
      tester,
      config: LlmProviderConfig.emptyForUser(
        7,
      ).copyWith(provider: 'deepseek', baseUrl: 'https://api.deepseek.com/v1'),
    );
    await reveal(tester, find.text('搜索和切换模型'));
    await tester.tap(find.text('搜索和切换模型'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '搜索模型名称或 ID'),
      'reasoner',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek Reasoner'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('field_模型 ID')))
          .controller!
          .text,
      'deepseek-reasoner',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('save persists before closing and reopening restores profiles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(440, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository();
    await show(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('provider_deepseek')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('field_API Key')),
      'deepseek-secret',
    );
    await tester.tap(find.byKey(const ValueKey('provider_opencode_go')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('field_API Key')),
      'go-secret',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repository.active?.provider, 'opencode_go');
    expect(repository.profiles['deepseek']?.apiKey, 'deepseek-secret');
    await tester.pumpWidget(const SizedBox());
    await show(tester, repository: repository, config: repository.active);
    await tester.tap(find.byKey(const ValueKey('provider_deepseek')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('field_API Key')))
          .controller!
          .text,
      'deepseek-secret',
    );
  });

  testWidgets('renders configuration preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 1600));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('PreviewChinese');
      loader.addFont(
        Future.value(ByteData.sublistView(font.readAsBytesSync())),
      );
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final boundary = GlobalKey();
    final config = LlmProviderConfig.emptyForUser(7).copyWith(
      provider: 'deepseek',
      apiKey: 'preview-only',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-v4-flash',
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'PreviewChinese', useMaterial3: true),
          home: LlmConfigEditPage(config: config),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await render.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/llm-config-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      img.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}

class _MemoryRepository extends LlmConfigRepository {
  final profiles = <String, LlmProviderConfig>{};
  LlmProviderConfig? active;
  @override
  Future<LlmProviderConfig?> getForProvider(
    int userId,
    String provider,
  ) async => profiles[provider];
  @override
  Future<void> saveProvider(LlmProviderConfig config) async {
    profiles[config.provider] = config;
  }

  @override
  Future<LlmProviderConfig> save(LlmProviderConfig config) async {
    await saveProvider(config);
    return active = config;
  }
}
