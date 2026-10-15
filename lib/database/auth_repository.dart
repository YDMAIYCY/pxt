import 'app_database.dart';
import 'models/user_profile.dart';
import 'password_hasher.dart';
import '../feishu/feishu_controller.dart';

// ========== 认证结果模型 ==========
// 统一返回登录、注册等认证动作的结果。

class AuthResult {
  const AuthResult({required this.success, required this.message, this.userId});

  final bool success;
  final String message;
  final int? userId;
}

// ========== 认证与资料仓库 ==========
// 管理注册、登录、会话恢复、资料更新和退出登录。

class AuthRepository {
  AuthRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> ensureInitialized() async {
    await _database.database;
  }

  // ========== 注册与登录 ==========

  Future<AuthResult> register({
    required String username,
    required String password,
  }) async {
    final trimmedUsername = username.trim();

    if (trimmedUsername.isEmpty || password.isEmpty) {
      return const AuthResult(success: false, message: '用户名和密码不能为空');
    }

    if (password.length < 6) {
      return const AuthResult(success: false, message: '密码长度至少 6 位');
    }

    try {
      final db = await _database.database;
      final now = DateTime.now().toUtc().toIso8601String();

      return db.transaction((txn) async {
        final existing = await txn.query(
          AppDatabase.tableUsers,
          columns: ['id'],
          where: 'username = ?',
          whereArgs: [trimmedUsername],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          return const AuthResult(success: false, message: '用户名已存在');
        }

        final salt = _generateSalt();
        final hash = _hashPassword(salt: salt, password: password);

        final userId = await txn.insert(AppDatabase.tableUsers, {
          'username': trimmedUsername,
          'password_hash': hash,
          'password_salt': salt,
          'display_name': trimmedUsername,
          'bio': _defaultBio,
          'gender': _defaultGender,
          'age': null,
          'avatar_style': ProfilePresetIds.defaultAvatarStyle,
          'background_style': ProfilePresetIds.defaultBackgroundStyle,
          'avatar_image_path': null,
          'background_image_path': null,
          'created_at': now,
          'updated_at': now,
          'is_active': 1,
        });

        await txn.insert(AppDatabase.tableKnowledgeLibraries, {
          'user_id': userId,
          'name': '默认知识库',
          'description': '系统为用户自动创建的默认知识库',
          'created_at': now,
          'updated_at': now,
        });

        return const AuthResult(success: true, message: '注册成功，请登录');
      });
    } catch (error) {
      return AuthResult(success: false, message: '注册失败：$error');
    }
  }

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final trimmedUsername = username.trim();

    if (trimmedUsername.isEmpty || password.isEmpty) {
      return const AuthResult(success: false, message: '用户名和密码不能为空');
    }

    try {
      final db = await _database.database;
      final users = await db.query(
        AppDatabase.tableUsers,
        columns: ['id', 'password_hash', 'password_salt', 'is_active'],
        where: 'username = ?',
        whereArgs: [trimmedUsername],
        limit: 1,
      );

      if (users.isEmpty) {
        return const AuthResult(success: false, message: '用户不存在，请先注册');
      }

      final user = users.first;
      final isActive = (user['is_active'] as int?) ?? 0;
      if (isActive != 1) {
        return const AuthResult(success: false, message: '该账号已被禁用');
      }

      final salt = user['password_salt'] as String;
      final savedHash = user['password_hash'] as String;

      if (!PasswordHasher.verify(
        salt: salt,
        password: password,
        storedHash: savedHash,
      )) {
        return const AuthResult(success: false, message: '密码错误');
      }

      final userId = user['id'] as int;
      final now = DateTime.now().toUtc().toIso8601String();

      await db.transaction((txn) async {
        await txn.update(
          AppDatabase.tableUsers,
          {
            'last_login_at': now,
            'updated_at': now,
            if (PasswordHasher.shouldRehash(savedHash))
              'password_hash': _hashPassword(salt: salt, password: password),
          },
          where: 'id = ?',
          whereArgs: [userId],
        );

        await txn.update(
          AppDatabase.tableAuthSessions,
          {'logged_out_at': now},
          where: 'user_id = ? AND logged_out_at IS NULL',
          whereArgs: [userId],
        );

        await txn.insert(AppDatabase.tableAuthSessions, {
          'user_id': userId,
          'session_token': _buildSessionToken(userId),
          'created_at': now,
        });
      });

      return AuthResult(success: true, message: '登录成功', userId: userId);
    } catch (error) {
      return AuthResult(success: false, message: '登录失败：$error');
    }
  }

  // ========== 当前会话 ==========

  Future<UserProfile?> getCurrentUserProfile() async {
    try {
      final db = await _database.database;
      final now = DateTime.now().toUtc().toIso8601String();

      final rows = await db.rawQuery(
        '''
        SELECT
          users.id,
          users.username,
          users.display_name,
          users.bio,
          users.gender,
          users.age,
          users.avatar_style,
          users.background_style,
          users.avatar_image_path,
          users.background_image_path,
          users.last_login_at
        FROM ${AppDatabase.tableAuthSessions} sessions
        INNER JOIN ${AppDatabase.tableUsers} users
          ON users.id = sessions.user_id
        WHERE sessions.logged_out_at IS NULL
          AND (sessions.expired_at IS NULL OR sessions.expired_at > ?)
          AND users.is_active = 1
        ORDER BY sessions.created_at DESC
        LIMIT 1
        ''',
        [now],
      );

      if (rows.isEmpty) {
        return null;
      }

      return UserProfile.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  Future<void> logoutCurrentUser() async {
    await FeishuController.signOut(_database);
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(AppDatabase.tableAuthSessions, {
      'logged_out_at': now,
    }, where: 'logged_out_at IS NULL');
  }

  // ========== 用户资料 ==========

  Future<UserProfile> saveUserProfile(UserProfile profile) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(
      AppDatabase.tableUsers,
      {...profile.toDatabaseMap(), 'updated_at': now},
      where: 'id = ?',
      whereArgs: [profile.id],
    );

    final rows = await db.query(
      AppDatabase.tableUsers,
      columns: [
        'id',
        'username',
        'display_name',
        'bio',
        'gender',
        'age',
        'avatar_style',
        'background_style',
        'avatar_image_path',
        'background_image_path',
        'last_login_at',
      ],
      where: 'id = ?',
      whereArgs: [profile.id],
      limit: 1,
    );

    return UserProfile.fromMap(rows.first);
  }

  // ========== 密码与会话工具 ==========

  String _generateSalt() {
    return PasswordHasher.generateSalt();
  }

  String _hashPassword({required String salt, required String password}) {
    return PasswordHasher.hash(salt: salt, password: password);
  }

  String _buildSessionToken(int userId) {
    return PasswordHasher.buildSessionToken(userId);
  }

  static const String _defaultBio = '记录今天的学习灵感，慢慢长成自己的知识库。';
  static const String _defaultGender = '保密';
}
