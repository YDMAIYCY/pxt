import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/auth_repository.dart';
import '../database/models/user_profile.dart';
import '../database/password_hasher.dart';
import 'cloud_backend.dart';

class CloudIdentityRepository {
  CloudIdentityRepository({AppDatabase? database, SupabaseClient? client})
    : _db = database ?? AppDatabase.instance,
      _client = client;
  final AppDatabase _db;
  final SupabaseClient? _client;
  SupabaseClient get client =>
      _client ??
      CloudBackend.instance.client ??
      (throw CloudFailure(CloudBackend.instance.failure ?? '云服务尚未就绪，请稍后重试'));

  Future<String?> linkedUuid(int userId) async {
    final rows = await (await _db.database).query(
      'cloud_identity_links',
      where: 'local_user_id=?',
      whereArgs: [userId],
    );
    return rows.firstOrNull?['auth_uuid'] as String?;
  }

  Future<String> requireLinked() async {
    final current = await AuthRepository(database: _db).getCurrentUserProfile();
    final uuid = client.auth.currentUser?.id;
    if (current == null || uuid == null) {
      throw const CloudFailure('请先登录智学帮');
    }
    if (await linkedUuid(current.id) != uuid) {
      throw const CloudFailure('登录状态需要更新，请重新登录智学帮');
    }
    return uuid;
  }

  /// A verified app login selects its own local space automatically. Only an
  /// explicitly requested legacy upgrade may reuse the current local user ID.
  Future<UserProfile> activateAuthenticatedUser({int? legacyUserId}) async {
    final verified = (await client.auth.getUser()).user;
    if (verified == null || verified.id != client.auth.currentUser?.id) {
      throw const CloudFailure('身份验证失败，请重新登录');
    }
    final auth = AuthRepository(database: _db);
    final local = await auth.getCurrentUserProfile();
    final db = await _db.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'cloud_identity_links',
        where: 'auth_uuid=?',
        whereArgs: [verified.id],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      int userId;
      if (legacyUserId != null) {
        if (local?.id != legacyUserId) {
          throw const CloudFailure('原账号登录状态已改变，请重新验证原账号');
        }
        final links = await txn.query(
          'cloud_identity_links',
          where: 'local_user_id=?',
          whereArgs: [legacyUserId],
        );
        if (links.isNotEmpty && links.single['auth_uuid'] != verified.id) {
          throw const CloudFailure('此账号已完成升级，请使用原来的邮箱登录');
        }
        if (existing.isNotEmpty &&
            existing.single['local_user_id'] != legacyUserId) {
          throw const CloudFailure('此邮箱已有其他学习资料，请选择使用其他账号登录');
        }
        if (links.isEmpty) {
          await txn.insert('cloud_identity_links', {
            'local_user_id': legacyUserId,
            'auth_uuid': verified.id,
            'linked_at': now,
          });
        }
        userId = legacyUserId;
      } else {
        if (existing.isNotEmpty) {
          userId = existing.single['local_user_id'] as int;
        } else {
          final salt = PasswordHasher.generateSalt();
          userId = await txn.insert('users', {
            'username': 'cloud_${verified.id}',
            // This random local password is not a second cloud credential.
            'password_hash': PasswordHasher.hash(
              salt: salt,
              password: const Uuid().v4(),
            ),
            'password_salt': salt,
            'display_name': _nickname(verified),
            'bio': '',
            'gender': '保密',
            'avatar_style': ProfilePresetIds.defaultAvatarStyle,
            'background_style': ProfilePresetIds.defaultBackgroundStyle,
            'created_at': now, 'updated_at': now, 'is_active': 1,
          });
          await txn.insert('knowledge_libraries', {
            'user_id': userId,
            'name': '默认知识库',
            'description': '',
            'created_at': now,
            'updated_at': now,
          });
          await txn.insert('cloud_identity_links', {
            'local_user_id': userId,
            'auth_uuid': verified.id,
            'linked_at': now,
          });
        }
      }
      final users = await txn.query(
        'users',
        where: 'id=? AND is_active=1',
        whereArgs: [userId],
      );
      if (users.isEmpty) throw const CloudFailure('账号资料不可用，请联系管理员');
      if (local?.id != userId) {
        await txn.update('auth_sessions', {
          'logged_out_at': now,
        }, where: 'logged_out_at IS NULL');
        await txn.insert('auth_sessions', {
          'user_id': userId,
          'session_token': PasswordHasher.buildSessionToken(userId),
          'created_at': now,
        });
      }
      await txn.update(
        'users',
        {'last_login_at': now},
        where: 'id=?',
        whereArgs: [userId],
      );
    });
    return (await auth.getCurrentUserProfile())!;
  }

  static String _nickname(User user) {
    final value = user.userMetadata?['nickname'];
    return value is String && value.trim().isNotEmpty
        ? value.trim().substring(0, value.trim().length.clamp(0, 12))
        : '新同学';
  }
}
