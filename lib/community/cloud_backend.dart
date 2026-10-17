import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_configuration.dart';

class CloudBackend extends ChangeNotifier {
  CloudBackend._();
  static final instance = CloudBackend._();
  SupabaseClient? client;
  String? failure;
  bool get configured => client != null;
  bool get signedIn => client?.auth.currentUser != null;

  Future<void> initialize() async {
    if (client != null) return;
    try {
      final configuration = await CloudConfiguration.load();
      final supabase = await Supabase.initialize(
        url: configuration.url,
        publishableKey: configuration.publishableKey,
        debug: false,
        httpClient: _TimeoutClient(),
        authOptions: FlutterAuthClientOptions(
          localStorage: const _SecureSessionStorage(),
          autoRefreshToken: true,
        ),
      );
      client = supabase.client;
      client!.auth.onAuthStateChange.listen(
        (event) {
          failure = event.event == AuthChangeEvent.signedOut
              ? '云端登录已退出，请重新登录'
              : null;
          notifyListeners();
        },
        onError: (Object _) {
          failure = '云端会话暂不可用，请检查网络或重新登录';
          notifyListeners();
        },
      );
    } on CloudConfigurationException catch (error) {
      failure = error.message;
    } catch (_) {
      failure = '云服务初始化失败，个人学习资料仍可正常使用';
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final auth = client?.auth;
    if (auth == null) return;
    try {
      await auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The SDK clears the local session before contacting the logout endpoint.
      // Offline revocation must not leave the SQLite account logged in.
      if (auth.currentSession != null) rethrow;
    } finally {
      if (auth.currentSession == null) {
        await const _SecureSessionStorage().removePersistedSession();
      }
    }
  }
}

class _TimeoutClient extends http.BaseClient {
  final _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner
        .send(request)
        .timeout(const Duration(seconds: 20));
    return http.StreamedResponse(
      response.stream.timeout(const Duration(seconds: 25)),
      response.statusCode,
      headers: response.headers,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

class _SecureSessionStorage extends LocalStorage {
  const _SecureSessionStorage();
  static const _storage = FlutterSecureStorage();
  static const _key = 'zhixuebang.supabase.session';
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

String cloudError(Object error) {
  if (error is CloudFailure) return error.message;
  if (error is TimeoutException) return '网络请求超时，请重试';
  if (error is AuthException) {
    if (error.code == 'invalid_credentials') return '邮箱或密码不正确';
    if (error.code == 'email_not_confirmed') return '请先到邮箱确认注册，再登录';
    if (error.code == 'user_already_exists') return '此邮箱已注册，请直接登录';
    if (error.code == 'email_provider_disabled') {
      return '云端尚未开启邮箱登录，请在 Supabase 的 Auth Providers 中启用 Email';
    }
    if (error.code == 'signup_disabled') {
      return '云端已关闭新用户注册，请在 Supabase 中重新开启';
    }
    if (error.code == 'over_email_send_rate_limit') {
      return '确认邮件发送过于频繁，请稍后再试；也可让管理员关闭邮箱确认';
    }
    if (error.code == 'over_request_rate_limit') return '操作过于频繁，请稍后重试';
    if (error.code == 'weak_password') return '密码强度不足，请改用更长的密码';
    if (error.code == 'validation_failed') {
      return '邮箱或密码格式不被接受，请检查后重试';
    }
    return '账号操作失败，请检查邮箱、密码或稍后重试';
  }
  if (error is PostgrestException) {
    if (error.code == '42501') return '没有操作权限，请检查登录状态及好友关系';
    if (error.code == '23505') return '这项内容已经提交，请刷新查看';
    if (error.code == 'PGRST205' || error.code == 'PGRST202') {
      return '云端数据库尚未部署，请先执行 Supabase 迁移';
    }
    if (error.code == '23514') return '内容格式不符合要求，请检查长度和附件';
    return '云端操作失败，请刷新后重试';
  }
  if (error is StorageException) return '图片上传或读取失败，请检查网络及图片格式';
  return '连接失败，请检查网络后重试';
}

class CloudFailure implements Exception {
  const CloudFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
