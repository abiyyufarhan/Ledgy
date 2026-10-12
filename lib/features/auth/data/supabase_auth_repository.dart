import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_repository.dart';
import '../domain/account_profile_repository.dart';
import 'cloud_connection.dart';

class SupabaseAuthRepository
    implements AuthRepository, AccountProfileRepository {
  SupabaseAuthRepository(this.connection);
  final CloudConnection connection;
  SupabaseClient get _client {
    final client = connection.client;
    if (client == null) {
      throw const AuthFailure(
        'Sinkronisasi cloud belum dikonfigurasi. Gunakan mode lokal dulu.',
      );
    }
    return client;
  }

  @override
  bool get configured => connection.client != null;
  CloudUser? _user(User? user) => user == null
      ? null
      : CloudUser(
          user.id,
          user.email ?? '',
          name:
              (user.userMetadata?['full_name'] ?? user.userMetadata?['name'])
                  as String?,
          avatarUrl: user.userMetadata?['avatar_url'] as String?,
          saverProfile: SaverProfile.fromCode(
            user.userMetadata?['saver_profile'],
          ),
        );
  @override
  CloudUser? get currentUser => _user(connection.client?.auth.currentUser);
  @override
  Stream<CloudUser?> get changes =>
      connection.client?.auth.onAuthStateChange.map(
        (state) => _user(state.session?.user),
      ) ??
      const Stream.empty();

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 30));
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login')) {
        throw const AuthFailure(
          'Email atau kata sandi salah. Periksa lalu coba lagi.',
        );
      }
      if (message.contains('email not confirmed')) {
        throw const AuthFailure(
          'Email belum dikonfirmasi. Buka tautan konfirmasi di email Anda.',
        );
      }
      if (message.contains('already registered')) {
        throw const AuthFailure('Email sudah terdaftar. Gunakan tab Masuk.');
      }
      if (message.contains('rate') || message.contains('too many')) {
        throw const AuthFailure(
          'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.',
        );
      }
      if (message.contains('password') &&
          (message.contains('weak') || message.contains('least'))) {
        throw const AuthFailure(
          'Kata sandi belum memenuhi ketentuan. Gunakan kata sandi lebih kuat.',
        );
      }
      throw const AuthFailure(
        'Permintaan akun gagal. Periksa koneksi dan konfigurasi Auth, lalu coba lagi.',
      );
    } on SocketException {
      throw const AuthFailure(
        'Tidak ada koneksi internet. Anda tetap dapat menggunakan mode lokal.',
      );
    } on TimeoutException {
      throw const AuthFailure(
        'Koneksi terlalu lama. Coba lagi saat internet stabil.',
      );
    } on AuthFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AuthFailure(
          'Hapus akun belum tersedia di cloud. Terapkan migrasi pengaturan profil terlebih dahulu.',
        );
      }
      throw const AuthFailure(
        'Permintaan akun belum berhasil. Coba lagi nanti.',
      );
    } catch (_) {
      throw const AuthFailure(
        'Belum dapat terhubung ke cloud. Coba lagi nanti.',
      );
    }
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _request(
      () => _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      ),
    );
  }

  @override
  Future<bool> signUp(
    String email,
    String password, {
    String? name,
    SaverProfile? saverProfile,
  }) async {
    final metadata = <String, dynamic>{
      if (name?.trim().isNotEmpty == true) 'full_name': name!.trim(),
      if (saverProfile != null) 'saver_profile': saverProfile.code,
    };
    final response = await _request(
      () => _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: connection.config.emailRedirect,
        data: metadata.isEmpty ? null : metadata,
      ),
    );
    return response.session != null;
  }

  @override
  Future<void> updateSaverProfile(SaverProfile profile) async {
    await _request(
      () => _client.auth.updateUser(
        UserAttributes(data: {'saver_profile': profile.code}),
      ),
    );
  }

  @override
  Future<void> updateName(String name) async {
    final value = name.trim();
    if (value.isEmpty) throw const AuthFailure('Nama wajib diisi.');
    await _request(
      () => _client.auth.updateUser(UserAttributes(data: {'full_name': value})),
    );
  }

  @override
  Future<void> updateEmail(String email) async {
    await _request(
      () => _client.auth.updateUser(
        UserAttributes(email: email.trim()),
        emailRedirectTo: connection.config.emailRedirect,
      ),
    );
  }

  @override
  Future<void> deleteAccount() async {
    if (currentUser == null) throw const AuthFailure('Masuk terlebih dahulu.');
    await _request(() => _client.rpc('ledgy_delete_account'));
    await signOut();
  }

  @override
  Future<void> resendConfirmation(String email) async {
    await _request(
      () => _client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: connection.config.emailRedirect,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    final client = _client;
    try {
      // The SDK removes/persists the local session BEFORE revoking it remotely.
      await client.auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      if (client.auth.currentUser != null) {
        throw const AuthFailure('Belum dapat keluar. Coba lagi.');
      }
    }
  }
}
