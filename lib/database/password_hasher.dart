import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

// ========== Password hashing ==========
// Keeps legacy SHA-256 verification while writing new PBKDF2-SHA256 hashes.
class PasswordHasher {
  const PasswordHasher._();

  static const int _saltByteLength = 16;
  static const int _tokenByteLength = 16;
  static const int _iterations = 100000;
  static const int _derivedKeyLength = 32;
  static const int _sha256DigestLength = 32;
  static const String _pbkdf2Prefix = 'pbkdf2_sha256';

  static String generateSalt({Random? random}) {
    final rng = random ?? Random.secure();
    final saltBytes = List<int>.generate(
      _saltByteLength,
      (_) => rng.nextInt(256),
    );
    return base64UrlEncode(saltBytes);
  }

  static String hash({required String salt, required String password}) {
    final derivedKey = _pbkdf2Sha256(
      password: utf8.encode(password),
      salt: utf8.encode(salt),
      iterations: _iterations,
      keyLength: _derivedKeyLength,
    );
    return '$_pbkdf2Prefix\$$_iterations\$${base64UrlEncode(derivedKey)}';
  }

  static bool verify({
    required String salt,
    required String password,
    required String storedHash,
  }) {
    final normalizedHash = storedHash.trim();
    if (normalizedHash.startsWith('$_pbkdf2Prefix\$')) {
      return _verifyPbkdf2(
        salt: salt,
        password: password,
        storedHash: normalizedHash,
      );
    }

    final legacyHash = sha256.convert(utf8.encode('$salt:$password'));
    return _constantTimeEquals(
      utf8.encode(legacyHash.toString()),
      utf8.encode(normalizedHash),
    );
  }

  static bool shouldRehash(String storedHash) {
    return !storedHash.trim().startsWith('$_pbkdf2Prefix\$');
  }

  static String buildSessionToken(int userId) {
    final rng = Random.secure();
    final tokenBytes = List<int>.generate(
      _tokenByteLength,
      (_) => rng.nextInt(256),
    );
    final randomToken = base64UrlEncode(tokenBytes);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$userId-$timestamp-$randomToken';
  }

  static bool _verifyPbkdf2({
    required String salt,
    required String password,
    required String storedHash,
  }) {
    final parts = storedHash.split(r'$');
    if (parts.length != 3 || parts.first != _pbkdf2Prefix) {
      return false;
    }

    final iterations = int.tryParse(parts[1]);
    final expectedKey = _tryDecodeBase64Url(parts[2]);
    if (iterations == null || iterations < 1 || expectedKey.isEmpty) {
      return false;
    }

    final actualKey = _pbkdf2Sha256(
      password: utf8.encode(password),
      salt: utf8.encode(salt),
      iterations: iterations,
      keyLength: expectedKey.length,
    );
    return _constantTimeEquals(actualKey, expectedKey);
  }

  static List<int> _pbkdf2Sha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, password);
    final blockCount = (keyLength / _sha256DigestLength).ceil();
    final derivedKey = <int>[];

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      final block = <int>[
        ...salt,
        (blockIndex >> 24) & 0xff,
        (blockIndex >> 16) & 0xff,
        (blockIndex >> 8) & 0xff,
        blockIndex & 0xff,
      ];
      var u = hmac.convert(block).bytes;
      final output = List<int>.of(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < output.length; j++) {
          output[j] ^= u[j];
        }
      }

      derivedKey.addAll(output);
    }

    return derivedKey.take(keyLength).toList(growable: false);
  }

  static List<int> _tryDecodeBase64Url(String value) {
    try {
      return base64Url.decode(value);
    } on FormatException {
      return const <int>[];
    }
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    var diff = 0;
    for (var i = 0; i < left.length; i++) {
      diff |= left[i] ^ right[i];
    }
    return diff == 0;
  }
}
