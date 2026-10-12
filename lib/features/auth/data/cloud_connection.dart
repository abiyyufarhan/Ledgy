import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'namespaced_auth_storage.dart';

class CloudConfig {
  const CloudConfig({
    required this.url,
    required this.publicKey,
    this.redirectUrl,
  });
  const CloudConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      publicKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
      redirectUrl = const String.fromEnvironment('SUPABASE_AUTH_REDIRECT_URL');

  final String url;
  final String publicKey;
  final String? redirectUrl;
  String get storageNamespace => 'ledgy-2.0-${Uri.parse(url).host}';
  String get sessionStorageKey => '$storageNamespace-auth-token';
  bool get provided =>
      url.isNotEmpty &&
      publicKey.isNotEmpty &&
      !url.contains('YOUR_PROJECT_REF') &&
      !publicKey.startsWith('YOUR_');

  bool get valid {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        publicKey.startsWith('sb_secret_')) {
      return false;
    }
    if (publicKey.startsWith('sb_publishable_')) return true;
    try {
      final parts = publicKey.split('.');
      if (parts.length != 3) return false;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return claims is Map && claims['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  String? get emailRedirect {
    if (redirectUrl != null && redirectUrl!.isNotEmpty) return redirectUrl;
    return Platform.isAndroid ? 'com.ledgy.ledgy2://auth/callback' : null;
  }
}

class CloudConnection {
  const CloudConnection({
    this.config = const CloudConfig(url: '', publicKey: ''),
    this.client,
    this.error,
  });
  final CloudConfig config;
  final SupabaseClient? client;
  final String? error;

  static Future<CloudConnection> initialize([
    CloudConfig config = const CloudConfig.fromEnvironment(),
  ]) async {
    if (!config.provided) return CloudConnection(config: config);
    if (!config.valid) {
      return CloudConnection(
        config: config,
        error: 'Konfigurasi cloud belum valid. Mode lokal tetap tersedia.',
      );
    }
    try {
      final supabase = await Supabase.initialize(
        url: config.url,
        publishableKey: config.publicKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: SharedPreferencesLocalStorage(
            persistSessionKey: config.sessionStorageKey,
          ),
          pkceAsyncStorage: NamespacedAuthStorage(
            namespace: config.storageNamespace,
            storage: SharedPreferencesGotrueAsyncStorage(),
          ),
          detectSessionInUriPredicate: (uri) {
            final allowed = Uri.parse(
              config.emailRedirect ?? 'com.ledgy.ledgy2://auth/callback',
            );
            return uri.scheme == allowed.scheme &&
                uri.host == allowed.host &&
                uri.path == allowed.path;
          },
        ),
      );
      return CloudConnection(config: config, client: supabase.client);
    } catch (_) {
      return CloudConnection(
        config: config,
        error: 'Cloud belum dapat disiapkan. Buka ulang aplikasi untuk mencoba lagi.',
      );
    }
  }
}
