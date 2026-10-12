import 'dart:async';

import 'package:ledgy/features/security/domain/app_lock.dart';
import 'package:ledgy/features/security/domain/lock_configuration.dart';

class MemoryLockPreferences implements SecureLockPreferences {
  LockConfiguration value = const LockConfiguration();
  bool failWrite = false;
  Completer<void>? pendingWrite;
  @override
  Future<bool> enabled() async => value.enabled;
  @override
  Future<void> setEnabled(bool enabled) async {
    value = value.copyWith(biometricEnabled: enabled);
  }

  @override
  Future<LockConfiguration> readConfiguration() async => value;
  @override
  Future<void> writeConfiguration(LockConfiguration next) async {
    if (pendingWrite != null) await pendingWrite!.future;
    if (failWrite) throw StateError('private');
    value = next;
  }
}

class FakePasswordHasher implements PasswordHasher {
  Completer<String>? pendingCreate;
  Completer<bool>? pendingVerify;
  int verifies = 0;
  @override
  Future<String> create(String password) async =>
      pendingCreate?.future ?? 'test-only:$password';
  @override
  Future<bool> verify(String password, String record) async {
    verifies++;
    return pendingVerify?.future ?? (record == 'test-only:$password');
  }
}

class FakeBiometrics implements DeviceAuthenticator {
  bool supported = false;
  bool accepted = true;
  int prompts = 0;
  Completer<bool>? pendingAvailability;
  @override
  Future<bool> available() async => pendingAvailability?.future ?? supported;
  @override
  Future<bool> authenticate() async {
    prompts++;
    return accepted;
  }
}
