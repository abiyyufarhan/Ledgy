import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../local/data/local_finance_repository.dart';
import '../domain/app_lock.dart';
import '../domain/lock_configuration.dart';

class LocalLockPreferences implements SecureLockPreferences {
  LocalLockPreferences(this.finance);
  final LocalFinanceRepository finance;
  @override
  Future<bool> enabled() async =>
      await finance.state('security:lock_enabled') == 'true';
  @override
  Future<void> setEnabled(bool value) =>
      finance.setState('security:lock_enabled', '$value');

  @override
  Future<LockConfiguration> readConfiguration() async {
    final value = await finance.state('security:lock_configuration');
    if (value != null) {
      return LockConfiguration.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
    }
    final previous = await enabled();
    return LockConfiguration(
      biometricEnabled: previous,
      legacyDeviceLock: previous,
    );
  }

  @override
  Future<void> writeConfiguration(LockConfiguration value) => finance.setState(
    'security:lock_configuration',
    jsonEncode(value.toJson()),
  );
}

class LocalDeviceAuthenticator implements DeviceAuthenticator {
  LocalDeviceAuthenticator({LocalAuthentication? auth, bool? isWindows})
    : _auth = auth ?? LocalAuthentication(),
      _windows = isWindows ?? Platform.isWindows;
  final LocalAuthentication _auth;
  final bool _windows;
  static const _channel = MethodChannel('com.ledgy.ledgy/biometrics');
  @override
  Future<bool> available() async {
    try {
      if (_windows) {
        // local_auth on Windows reports PIN-only Hello as biometric support.
        // Require a biometric unit reported by Windows before enabling it.
        return await _channel.invokeMethod<bool>('hasBiometricHardware') ==
                true &&
            await _auth.isDeviceSupported();
      }
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() => _auth.authenticate(
    localizedReason: 'Buka Ledgy untuk melihat keuangan Anda',
    biometricOnly: !_windows,
    persistAcrossBackgrounding: false,
  );
}
