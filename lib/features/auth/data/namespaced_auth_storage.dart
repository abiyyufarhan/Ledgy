import 'package:supabase_flutter/supabase_flutter.dart';

/// Keep pending email verification flows separate from the stable app.
class NamespacedAuthStorage extends GotrueAsyncStorage {
  NamespacedAuthStorage({required this.namespace, required this.storage});

  final String namespace;
  final GotrueAsyncStorage storage;

  @override
  Future<String?> getItem({required String key}) =>
      storage.getItem(key: '$namespace-$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      storage.setItem(key: '$namespace-$key', value: value);

  @override
  Future<void> removeItem({required String key}) =>
      storage.removeItem(key: '$namespace-$key');
}
