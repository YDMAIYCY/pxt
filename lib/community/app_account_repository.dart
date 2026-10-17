import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../database/auth_repository.dart';
import '../database/models/user_profile.dart';
import 'cloud_backend.dart';
import 'cloud_identity_repository.dart';
import 'community_repository.dart';

/// Supabase is the app's only registration/login authority. SQLite user IDs
/// remain private ownership keys, provisioned automatically after a verified login.
class AppAccountRepository {
  AppAccountRepository({AppDatabase? database, SupabaseClient? client})
    : _database = database ?? AppDatabase.instance,
      _client = client;
  final AppDatabase _database;
  final SupabaseClient? _client;
  SupabaseClient? get _availableClient =>
      _client ?? CloudBackend.instance.client;
  SupabaseClient get _supabase =>
      _availableClient ??
      (throw CloudFailure(CloudBackend.instance.failure ?? '登录服务暂不可用，请稍后重试'));
  AuthRepository get _local => AuthRepository(database: _database);
  CloudIdentityRepository get _identity =>
      CloudIdentityRepository(database: _database, client: _supabase);

  Future<UserProfile?> offlineUser() => _local.getCurrentUserProfile();

  Future<UserProfile?> legacyUser() async {
    final local = await _local.getCurrentUserProfile();
    if (local == null) return null;
    final rows = await (await _database.database).query(
      'cloud_identity_links',
      where: 'local_user_id=?',
      whereArgs: [local.id],
    );
    return rows.isEmpty ? local : null;
  }

  Future<UserProfile?> restoreSession() async {
    final local = await _local.getCurrentUserProfile();
    final client = _availableClient;
    // An initialization/network failure must not lock away existing learning data.
    if (client == null) return local;
    var session = client.auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      try {
        session = (await client.auth.refreshSession()).session;
      } on AuthException catch (error) {
        if (error.statusCode == '400' ||
            error.statusCode == '401' ||
            error.statusCode == '403') {
          return null;
        }
        return await _matchingLocal(local, client.auth.currentUser?.id);
      } catch (_) {
        return await _matchingLocal(local, client.auth.currentUser?.id);
      }
    }
    if (session == null) return null;
    final matching = await _matchingLocal(local, session.user.id);
    if (matching != null) return matching;
    // Old learning data is adopted only from the explicit account-upgrade form.
    if (await legacyUser() != null) return null;
    return _identity.activateAuthenticatedUser();
  }

  Future<UserProfile?> _matchingLocal(UserProfile? local, String? uuid) async {
    if (local == null || uuid == null) return null;
    return await _identity.linkedUuid(local.id) == uuid ? local : null;
  }

  Future<void> _checkLegacy(int? userId) async {
    if (userId != null && (await legacyUser())?.id != userId) {
      throw const CloudFailure('原账号登录状态已改变，请重新验证原账号');
    }
  }

  void _validate(String email, String password) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim()) ||
        password.isEmpty) {
      throw const CloudFailure('请输入有效邮箱和密码');
    }
  }

  Future<UserProfile> signIn({
    required String email,
    required String password,
    int? legacyUserId,
  }) async {
    _validate(email, password);
    await _checkLegacy(legacyUserId);
    await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return _finishLogin(legacyUserId);
  }

  Future<void> resetPassword(String email) async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      throw const CloudFailure('请输入有效邮箱地址');
    }
    await _supabase.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> resendConfirmation(String email) async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      throw const CloudFailure('请输入有效邮箱地址');
    }
    await _supabase.auth.resend(type: OtpType.signup, email: email.trim());
  }

  Future<UserProfile?> register({
    required String email,
    required String password,
    required String nickname,
    int? legacyUserId,
  }) async {
    _validate(email, password);
    if (password.length < 8) throw const CloudFailure('密码长度至少 8 位');
    if (nickname.trim().isEmpty || nickname.trim().length > 12) {
      throw const CloudFailure('昵称请填写 1 至 12 个字');
    }
    await _checkLegacy(legacyUserId);
    final result = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'nickname': nickname.trim()},
    );
    if (result.session == null) return null;
    return _finishLogin(legacyUserId);
  }

  Future<UserProfile> _finishLogin(int? legacyUserId) async {
    try {
      final local = await _identity.activateAuthenticatedUser(
        legacyUserId: legacyUserId,
      );
      // Profile preferences are optional here: an undeployed community or network
      // outage must not undo an already successful app identity login.
      try {
        final community = CommunityRepository(
          client: _supabase,
          identity: _identity,
        );
        final remote = await community.profile(_supabase.auth.currentUser!.id);
        if (remote['nickname'] == '新同学' && local.primaryName != '新同学') {
          await community.saveProfile(
            nickname: local.primaryName,
            bio: local.bio,
          );
        } else if (legacyUserId == null) {
          return await _local.saveUserProfile(
            local.copyWith(
              displayName: remote['nickname'] as String,
              bio: remote['bio'] as String,
            ),
          );
        }
      } catch (_) {
        /* Keep authenticated local access if public profile sync fails. */
      }
      return local;
    } catch (_) {
      await _supabase.auth.signOut(scope: SignOutScope.local);
      rethrow;
    }
  }

  Future<UserProfile?> openLegacySpace({
    required String username,
    required String password,
  }) async {
    // Mapped accounts must always authenticate with Supabase, even if they still
    // have a legacy local password hash. Only an unupgraded account is eligible.
    final rows = await (await _database.database).rawQuery(
      '''
      SELECT users.id FROM users LEFT JOIN cloud_identity_links links
      ON links.local_user_id=users.id WHERE users.username=? AND links.auth_uuid IS NULL
    ''',
      [username.trim()],
    );
    if (rows.isEmpty) throw const CloudFailure('未找到待升级的原账号，请使用邮箱登录');
    final result = await _local.login(username: username, password: password);
    if (!result.success) throw const CloudFailure('原用户名或密码不正确');
    return legacyUser();
  }
}
