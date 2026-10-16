import 'dart:convert';
import 'package:flutter/services.dart';

class CloudConfiguration {
  const CloudConfiguration._(this.url, this.publishableKey);
  final String url;
  final String publishableKey;
  static const assetPath = 'assets/config/supabase.public.json';

  factory CloudConfiguration.fromJson(Map<String, dynamic> values) {
    final url = (values['SUPABASE_URL'] as String? ?? '').trim();
    final key = (values['SUPABASE_PUBLISHABLE_KEY'] as String? ?? '').trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const CloudConfigurationException('安装包中的云服务地址无效，请更新应用');
    }
    if (!key.startsWith('sb_publishable_')) {
      throw const CloudConfigurationException('安装包中的云服务公开配置无效，请更新应用');
    }
    return CloudConfiguration._(url.replaceFirst(RegExp(r'/$'), ''), key);
  }

  static Future<CloudConfiguration> load({
    AssetBundle? bundle,
    String environmentUrl = const String.fromEnvironment('SUPABASE_URL'),
    String environmentKey = const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    ),
  }) async {
    if (environmentUrl.isNotEmpty || environmentKey.isNotEmpty) {
      return CloudConfiguration.fromJson({
        'SUPABASE_URL': environmentUrl,
        'SUPABASE_PUBLISHABLE_KEY': environmentKey,
      });
    }
    String source;
    try {
      source = await (bundle ?? rootBundle).loadString(assetPath);
    } catch (_) {
      throw const CloudConfigurationException(
        '当前安装包未启用云服务，请安装已配置的版本；本地学习资料不受影响',
      );
    }
    try {
      return CloudConfiguration.fromJson(
        Map<String, dynamic>.from(jsonDecode(source) as Map),
      );
    } on CloudConfigurationException {
      rethrow;
    } catch (_) {
      throw const CloudConfigurationException('安装包中的云服务配置无法读取，请更新应用');
    }
  }
}

class CloudConfigurationException implements Exception {
  const CloudConfigurationException(this.message);
  final String message;
}
