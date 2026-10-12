import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../domain/lock_configuration.dart';

class Pbkdf2PasswordHasher implements PasswordHasher {
  static const iterations = 600000;

  static Future<List<int>> _derive(String password, List<int> salt) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    return key.extractBytes();
  }

  @override
  Future<String> create(String password) => Isolate.run(() async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await _derive(password, salt);
    return jsonEncode({
      'algorithm': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'hash': base64Encode(hash),
    });
  });

  @override
  Future<bool> verify(String password, String record) => Isolate.run(() async {
    final data = jsonDecode(record) as Map<String, dynamic>;
    if (data['algorithm'] != 'pbkdf2-sha256' ||
        data['iterations'] != iterations) {
      throw const FormatException('Invalid password record');
    }
    final salt = base64Decode(data['salt'] as String);
    final expected = base64Decode(data['hash'] as String);
    if (salt.length != 16 || expected.length != 32) {
      throw const FormatException('Invalid password record');
    }
    final actual = await _derive(password, salt);
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  });
}
