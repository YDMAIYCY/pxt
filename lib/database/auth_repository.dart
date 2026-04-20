import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'app_database.dart';

class AuthResult {
  const AuthResult({required this.success, required this.message, this.userId});

  final bool success;
  final String message;
  final int? userId;
}

class AuthRepository {
  AuthRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> ensureInitialized() async {
    await _database.database;
  }

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
        return const AuthResult(success: false, message: '用户已被禁用');
      }

      final salt = user['password_salt'] as String;
      final savedHash = user['password_hash'] as String;
      final currentHash = _hashPassword(salt: salt, password: password);

      if (savedHash != currentHash) {
        return const AuthResult(success: false, message: '密码错误');
      }

      final userId = user['id'] as int;
      final now = DateTime.now().toUtc().toIso8601String();

      await db.transaction((txn) async {
        await txn.update(
          AppDatabase.tableUsers,
          {'last_login_at': now, 'updated_at': now},
          where: 'id = ?',
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

  String _generateSalt() {
    final random = Random();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(saltBytes);
  }

  String _hashPassword({required String salt, required String password}) {
    final source = '$salt:$password';
    final digest = sha256.convert(utf8.encode(source));
    return digest.toString();
  }

  String _buildSessionToken(int userId) {
    final random = Random();
    final tokenBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final randomToken = base64UrlEncode(tokenBytes);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$userId-$timestamp-$randomToken';
  }
}
