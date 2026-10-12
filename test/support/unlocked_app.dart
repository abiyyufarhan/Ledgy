import 'package:ledgy/features/security/domain/app_lock.dart';

class TestLockPreferences implements LockPreferences {
  @override
  Future<bool> enabled() async => false;
  @override
  Future<void> setEnabled(bool value) async {}
}

class TestDeviceAuthenticator implements DeviceAuthenticator {
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> authenticate() async => true;
}

AppLock unlockedTestApp() =>
    AppLock(TestLockPreferences(), TestDeviceAuthenticator())
      ..ready = true
      ..locked = false;
