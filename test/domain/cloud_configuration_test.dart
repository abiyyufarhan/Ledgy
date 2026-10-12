import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ledgy/features/auth/data/cloud_connection.dart';
import 'package:ledgy/features/auth/data/namespaced_auth_storage.dart';

class _MemoryStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      values[key] = value;
  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

void main() {
  test('Client accepts public keys and rejects privileged credentials', () {
    expect(
      const CloudConfig(
        url: 'https://example.supabase.co',
        publicKey: 'sb_publishable_example',
      ).valid,
      isTrue,
    );
    for (final key in [
      'sb_secret_example',
      'invalid',
      'YOUR_PUBLIC_ANON_KEY',
    ]) {
      expect(
        CloudConfig(url: 'https://example.supabase.co', publicKey: key).valid,
        isFalse,
      );
    }
  });

  test('Session keys isolate both app versions and backend projects', () {
    const config = CloudConfig(
      url: 'https://example.supabase.co',
      publicKey: 'sb_publishable_example',
    );
    expect(config.sessionStorageKey, isNot('sb-example-auth-token'));
    expect(config.sessionStorageKey, startsWith('ledgy-2.0-'));
    expect(
      config.sessionStorageKey,
      isNot(
        const CloudConfig(
          url: 'https://other.supabase.co',
          publicKey: '',
        ).sessionStorageKey,
      ),
    );
  });

  test(
    'Updating and clearing a 2.0 PKCE verifier preserves stable storage',
    () async {
      final backend = _MemoryStorage();
      await backend.setItem(key: 'code-verifier', value: 'stable-verifier');
      final v2 = NamespacedAuthStorage(
        namespace: 'ledgy-2.0',
        storage: backend,
      );
      await v2.setItem(key: 'code-verifier', value: 'v2-verifier');
      expect(await v2.getItem(key: 'code-verifier'), 'v2-verifier');
      expect(await backend.getItem(key: 'code-verifier'), 'stable-verifier');
      await v2.removeItem(key: 'code-verifier');
      expect(await v2.getItem(key: 'code-verifier'), isNull);
      expect(await backend.getItem(key: 'code-verifier'), 'stable-verifier');
    },
  );
}
