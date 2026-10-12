import 'dart:async';

import 'lock_configuration.dart';

abstract interface class LockPreferences {
  Future<bool> enabled();
  Future<void> setEnabled(bool value);
}

abstract interface class DeviceAuthenticator {
  Future<bool> available();
  Future<bool> authenticate();
}

abstract interface class SecureLockPreferences implements LockPreferences {
  Future<LockConfiguration> readConfiguration();
  Future<void> writeConfiguration(LockConfiguration value);
}

/// The UI remains covered until authentication succeeds. A background event
/// invalidates an outstanding prompt so its late result cannot unlock the app.
class AppLock {
  AppLock(
    this.preferences,
    this.authenticator, {
    this.passwordHasher,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final LockPreferences preferences;
  final DeviceAuthenticator authenticator;
  final PasswordHasher? passwordHasher;
  final DateTime Function() _now;
  LockConfiguration _configuration = const LockConfiguration();
  final _changes = StreamController<int>.broadcast();
  Stream<int> get changes => _changes.stream;
  int _revision = 0;
  bool ready = false;
  bool get enabled => _configuration.enabled;
  bool get biometricEnabled => _configuration.biometricEnabled;
  bool get passwordEnabled => _configuration.passwordRecord != null;
  bool? biometricAvailable;
  bool locked = true;
  bool authenticating = false;
  bool backgrounded = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) _changes.add(++_revision);
  }

  Future<void> initialize() async {
    try {
      final storage = preferences;
      if (storage is SecureLockPreferences) {
        _configuration = await storage.readConfiguration();
      } else {
        final previous = await preferences.enabled();
        _configuration = LockConfiguration(
          biometricEnabled: previous,
          legacyDeviceLock: previous,
        );
      }
      locked = enabled;
      ready = true;
    } catch (_) {
      error = 'Pengaturan keamanan belum dapat dibaca. Coba lagi.';
    }
    _notify();
  }

  Future<void> refreshBiometrics() async {
    biometricAvailable = null;
    _notify();
    try {
      biometricAvailable = await authenticator.available();
    } catch (_) {
      biometricAvailable = false;
    }
    _notify();
  }

  Future<void> _save(LockConfiguration value) async {
    final storage = preferences;
    if (storage is SecureLockPreferences) {
      await storage.writeConfiguration(value);
    } else {
      if (value.passwordRecord != null) {
        throw StateError('Password storage unavailable');
      }
      await preferences.setEnabled(value.enabled);
    }
    _configuration = value;
  }

  Future<bool> _checkPassword(String? password) async {
    final retry = _configuration.retryAfter;
    if (retry != null && retry.isAfter(_now())) {
      error =
          'Terlalu banyak percobaan. Coba lagi dalam ${retry.difference(_now()).inSeconds + 1} detik.';
      return false;
    }
    if (password == null ||
        password.isEmpty ||
        passwordHasher == null ||
        !passwordEnabled) {
      error = 'Masukkan password Ledgy saat ini.';
      return false;
    }
    final accepted = await passwordHasher!.verify(
      password,
      _configuration.passwordRecord!,
    );
    if (accepted) {
      await _save(_configuration.copyWith(failedAttempts: 0, clearRetry: true));
    } else {
      final failures = _configuration.failedAttempts + 1;
      await _save(
        _configuration.copyWith(
          failedAttempts: failures,
          retryAfter: failures >= 5
              ? _now().add(const Duration(seconds: 30))
              : null,
        ),
      );
      error = failures >= 5
          ? 'Terlalu banyak percobaan. Coba lagi dalam 30 detik.'
          : 'Password Ledgy salah.';
    }
    return accepted;
  }

  Future<bool> unlock({String? password}) async {
    if (!ready || !locked || authenticating || backgrounded) return false;
    final generation = _generation;
    authenticating = true;
    error = null;
    _notify();
    try {
      final bool accepted;
      if (password != null) {
        accepted = await _checkPassword(password);
      } else if (biometricEnabled) {
        if (!_configuration.legacyDeviceLock &&
            !await authenticator.available()) {
          error = 'Biometrik tidak tersedia. Gunakan password Ledgy jika sudah diaktifkan.';
          return false;
        }
        accepted = await authenticator.authenticate();
      } else {
        error = 'Masukkan password Ledgy untuk membuka aplikasi.';
        return false;
      }
      if (generation != _generation || backgrounded) return false;
      if (accepted) {
        locked = false;
      } else {
        error ??= 'Aplikasi tetap terkunci. Coba lagi.';
      }
      return accepted;
    } catch (_) {
      error = 'Autentikasi belum berhasil. Periksa pengaturan keamanan lalu coba lagi.';
      return false;
    } finally {
      authenticating = false;
      _notify();
    }
  }

  Future<bool> configure(bool value, {String? password}) async {
    if (!ready || locked || authenticating || backgrounded) return false;
    authenticating = true;
    error = null;
    final generation = _generation;
    _notify();
    try {
      if (passwordEnabled && !await _checkPassword(password)) return false;
      if (value && !await authenticator.available()) {
        biometricAvailable = false;
        error =
            'Biometrik tidak tersedia atau belum disiapkan pada perangkat ini.';
        return false;
      }
      if ((value || !passwordEnabled) && !await authenticator.authenticate()) {
        error = 'Verifikasi perangkat dibatalkan. Pengaturan tetap sama.';
        return false;
      }
      if (generation != _generation || backgrounded) return false;
      await _save(
        _configuration.copyWith(
          biometricEnabled: value,
          legacyDeviceLock: false,
        ),
      );
      if (generation != _generation || backgrounded) {
        locked = enabled;
        return false;
      }
      locked = false;
      return true;
    } catch (_) {
      error = 'Pengaturan kunci belum dapat disimpan. Coba lagi.';
      return false;
    } finally {
      authenticating = false;
      _notify();
    }
  }

  Future<bool> setPassword(
    String? newPassword, {
    String? currentPassword,
  }) async {
    if (!ready || locked || authenticating || backgrounded) return false;
    if (newPassword != null &&
        (newPassword.runes.length < 8 || newPassword.runes.length > 128)) {
      error = 'Gunakan password 8–128 karakter. Huruf, angka, dan simbol diperbolehkan.';
      _notify();
      return false;
    }
    final generation = _generation;
    authenticating = true;
    error = null;
    _notify();
    try {
      if (passwordEnabled) {
        if (!await _checkPassword(currentPassword)) return false;
      } else if (biometricEnabled && !await authenticator.authenticate()) {
        error = 'Verifikasi perangkat dibatalkan. Pengaturan tetap sama.';
        return false;
      }
      if (generation != _generation || backgrounded) return false;
      final record = newPassword == null
          ? null
          : await passwordHasher!.create(newPassword);
      if (generation != _generation || backgrounded) return false;
      await _save(
        _configuration.copyWith(
          passwordRecord: record,
          clearPassword: newPassword == null,
          failedAttempts: 0,
          clearRetry: true,
        ),
      );
      if (generation != _generation || backgrounded) {
        locked = enabled;
        return false;
      }
      return true;
    } catch (_) {
      error = 'Pengaturan password belum dapat disimpan. Coba lagi.';
      return false;
    } finally {
      authenticating = false;
      _notify();
    }
  }

  void background() {
    backgrounded = true;
    _generation++;
    if (enabled) locked = true;
    _notify();
  }

  void resume() {
    backgrounded = false;
    _notify();
  }

  void lockNow() {
    if (enabled) {
      _generation++;
      locked = true;
      _notify();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _changes.close();
  }
}
