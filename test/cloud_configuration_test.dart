import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/community/cloud_configuration.dart';

class ConfigurationBundle extends CachingAssetBundle {
  ConfigurationBundle(this.source);
  final String? source;
  int reads = 0;

  @override
  Future<ByteData> load(String key) async {
    expect(key, CloudConfiguration.assetPath);
    reads++;
    if (source == null) throw StateError('asset missing');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source!)));
  }
}

void main() {
  const projectUrl = 'https://example.supabase.co';
  const publicKey = 'sb_publishable_test_fixture';
  Map<String, dynamic> values({
    String url = projectUrl,
    String key = publicKey,
  }) => {'SUPABASE_URL': url, 'SUPABASE_PUBLISHABLE_KEY': key};

  test('普通启动从安装包读取公开配置，无需 dart-define', () async {
    final bundle = ConfigurationBundle(jsonEncode(values(url: '$projectUrl/')));
    final configuration = await CloudConfiguration.load(bundle: bundle);
    expect(configuration.url, projectUrl);
    expect(configuration.publishableKey, publicKey);
    expect(bundle.reads, 1);
  });

  test('完整环境参数覆盖安装包，避免混用两个项目', () async {
    final bundle = ConfigurationBundle(null);
    final configuration = await CloudConfiguration.load(
      bundle: bundle,
      environmentUrl: projectUrl,
      environmentKey: publicKey,
    );
    expect(configuration.url, projectUrl);
    expect(bundle.reads, 0);
  });

  test('缺少一半环境参数时拒绝混用安装包配置', () async {
    final bundle = ConfigurationBundle(jsonEncode(values()));
    await expectLater(
      CloudConfiguration.load(bundle: bundle, environmentUrl: projectUrl),
      throwsA(isA<CloudConfigurationException>()),
    );
    expect(bundle.reads, 0);
  });

  test('缺少包内配置时显示中文安装包错误', () async {
    await expectLater(
      CloudConfiguration.load(bundle: ConfigurationBundle(null)),
      throwsA(
        isA<CloudConfigurationException>().having(
          (error) => error.message,
          'message',
          contains('当前安装包未启用云服务'),
        ),
      ),
    );
  });

  test('拒绝控制台地址、非 HTTPS 和带凭据的地址', () {
    for (final url in [
      'https://supabase.com/dashboard/project/example',
      'http://example.supabase.co',
      'https://user:password@example.supabase.co',
      '$projectUrl?token=hidden',
      '$projectUrl#hidden',
    ]) {
      expect(
        () => CloudConfiguration.fromJson(values(url: url)),
        throwsA(isA<CloudConfigurationException>()),
      );
    }
  });

  test('拒绝服务端密钥，错误文案不包含配置原值', () {
    for (final key in ['sb_secret_test_fixture', 'service_role_test_fixture']) {
      expect(
        () => CloudConfiguration.fromJson(values(key: key)),
        throwsA(
          isA<CloudConfigurationException>().having(
            (error) => error.message,
            'sanitized message',
            isNot(contains(key)),
          ),
        ),
      );
    }
  });

  test('损坏 JSON 或错误字段类型均转成配置错误', () async {
    for (final source in ['{not json', '[]', '{"SUPABASE_URL":123}']) {
      await expectLater(
        CloudConfiguration.load(bundle: ConfigurationBundle(source)),
        throwsA(isA<CloudConfigurationException>()),
      );
    }
  });
}
