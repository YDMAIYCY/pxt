import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/password_hasher.dart';

void main() {
  group('PasswordHasher', () {
    test('verifies PBKDF2 hashes and rejects wrong passwords', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(salt: salt, password: 'secret-123');

      expect(hash, startsWith('pbkdf2_sha256\$'));
      expect(
        PasswordHasher.verify(
          salt: salt,
          password: 'secret-123',
          storedHash: hash,
        ),
        isTrue,
      );
      expect(
        PasswordHasher.verify(
          salt: salt,
          password: 'wrong',
          storedHash: hash,
        ),
        isFalse,
      );
    });

    test('keeps legacy SHA-256 password hashes verifiable for upgrades', () {
      const salt = 'legacy-salt';
      final legacyHash = sha256.convert(utf8.encode('$salt:secret-123'));

      expect(
        PasswordHasher.verify(
          salt: salt,
          password: 'secret-123',
          storedHash: legacyHash.toString(),
        ),
        isTrue,
      );
      expect(PasswordHasher.shouldRehash(legacyHash.toString()), isTrue);
    });
  });
}
