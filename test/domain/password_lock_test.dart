import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/security/data/lock_repository.dart';
import 'package:ledgy/features/security/data/password_hasher.dart';
import 'package:ledgy/features/security/domain/app_lock.dart';

import '../support/password_lock.dart';

void main() {
  test('passwords use independent random salts and reject wrong or corrupt records', () async {
    final hasher = Pbkdf2PasswordHasher();
    const password = 'AbcXYZ123!@# +-*/';
    final first = await hasher.create(password);
    final second = await hasher.create(password);
    expect(first, isNot(second));
    expect(first, isNot(contains(password)));
    expect(jsonDecode(first)['iterations'], 600000);
    expect(await hasher.verify(password, first), isTrue);
    expect(await hasher.verify('abcXYZ123!@# +-*/', first), isFalse);
    await expectLater(hasher.verify(password, '{}'), throwsFormatException);
  });

  test('password works without biometrics, survives restart, and changes require old password', () async {
    final prefs = MemoryLockPreferences();
    final auth = FakeBiometrics();
    final lock = AppLock(prefs, auth, passwordHasher: FakePasswordHasher());
    addTearDown(lock.dispose);
    await lock.initialize();
    expect(await lock.configure(true), isFalse);
    expect(auth.prompts, 0);
    expect(await lock.setPassword('AbcXYZ123!@#'), isTrue);
    expect(lock.passwordEnabled, isTrue);
    final restarted = AppLock(
      prefs,
      auth,
      passwordHasher: FakePasswordHasher(),
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(restarted.locked, isTrue);
    expect(await restarted.configure(false), isFalse);
    expect(await restarted.unlock(password: 'wrong'), isFalse);
    expect(restarted.locked, isTrue);
    expect(await restarted.unlock(password: 'AbcXYZ123!@#'), isTrue);
    expect(
      await restarted.setPassword('newpass!1', currentPassword: 'wrong'),
      isFalse,
    );
    expect(
      await restarted.setPassword(null, currentPassword: 'wrong'),
      isFalse,
    );
    expect(restarted.passwordEnabled, isTrue);
    expect(
      await restarted.setPassword('newpass!1', currentPassword: 'AbcXYZ123!@#'),
      isTrue,
    );
    restarted.lockNow();
    expect(await restarted.unlock(password: 'AbcXYZ123!@#'), isFalse);
    expect(await restarted.unlock(password: 'newpass!1'), isTrue);
    expect(
      await restarted.setPassword(null, currentPassword: 'newpass!1'),
      isTrue,
    );
    expect(restarted.enabled, isFalse);
  });

  test(
    'combined methods allow either and a missing sensor cannot bypass the lock',
    () async {
      final auth = FakeBiometrics()..supported = true;
      final lock = AppLock(
        MemoryLockPreferences(),
        auth,
        passwordHasher: FakePasswordHasher(),
      );
      addTearDown(lock.dispose);
      await lock.initialize();
      expect(await lock.setPassword('Abc123!#'), isTrue);
      expect(await lock.configure(true, password: 'wrong'), isFalse);
      expect(auth.prompts, 0);
      auth.accepted = false;
      expect(await lock.configure(true, password: 'Abc123!#'), isFalse);
      auth.accepted = true;
      expect(await lock.configure(true, password: 'Abc123!#'), isTrue);
      lock.lockNow();
      expect(await lock.unlock(), isTrue);
      lock.lockNow();
      auth.supported = false;
      final prompts = auth.prompts;
      expect(await lock.unlock(), isFalse);
      expect(auth.prompts, prompts);
      expect(await lock.unlock(password: 'Abc123!#'), isTrue);
      expect(await lock.configure(false, password: 'Abc123!#'), isTrue);
      expect(lock.passwordEnabled, isTrue);
      expect(lock.biometricEnabled, isFalse);
    },
  );

  test('password retry cooldown persists across restart', () async {
    var time = DateTime(2026, 10, 8);
    final prefs = MemoryLockPreferences();
    final hasher = FakePasswordHasher();
    final lock = AppLock(
      prefs,
      FakeBiometrics(),
      passwordHasher: hasher,
      now: () => time,
    );
    addTearDown(lock.dispose);
    await lock.initialize();
    await lock.setPassword('Password!123');
    lock.lockNow();
    for (var i = 0; i < 5; i++) {
      expect(await lock.unlock(password: 'wrong'), isFalse);
    }
    final restarted = AppLock(
      prefs,
      FakeBiometrics(),
      passwordHasher: hasher,
      now: () => time,
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(await restarted.unlock(password: 'Password!123'), isFalse);
    expect(hasher.verifies, 5);
    time = time.add(const Duration(seconds: 31));
    expect(await restarted.unlock(password: 'Password!123'), isTrue);
    expect(prefs.value.failedAttempts, 0);
    expect(prefs.value.retryAfter, isNull);
  });

  test('background during password verification or configuration never exposes data', () async {
    final prefs = MemoryLockPreferences();
    final hasher = FakePasswordHasher();
    final lock = AppLock(prefs, FakeBiometrics(), passwordHasher: hasher);
    addTearDown(lock.dispose);
    await lock.initialize();
    prefs.pendingWrite = Completer<void>();
    final enabling = lock.setPassword('Password!123');
    await Future<void>.delayed(Duration.zero);
    lock.background();
    lock.resume();
    prefs.pendingWrite!.complete();
    expect(await enabling, isFalse);
    expect(lock.passwordEnabled, isTrue);
    expect(lock.locked, isTrue);
    prefs.pendingWrite = null;
    hasher.pendingVerify = Completer<bool>();
    final unlocking = lock.unlock(password: 'Password!123');
    lock.background();
    lock.resume();
    hasher.pendingVerify!.complete(true);
    expect(await unlocking, isFalse);
    expect(lock.locked, isTrue);
  });

  test(
    'failed storage does not enable a password that was not saved',
    () async {
      final prefs = MemoryLockPreferences()..failWrite = true;
      final lock = AppLock(
        prefs,
        FakeBiometrics(),
        passwordHasher: FakePasswordHasher(),
      );
      addTearDown(lock.dispose);
      await lock.initialize();
      expect(await lock.setPassword('Password!123'), isFalse);
      expect(lock.enabled, isFalse);
      expect(lock.error, isNot(contains('private')));
    },
  );

  test('SQLite settings preserve previous device locks, persist new methods, and fail closed if corrupt', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final finance = LocalFinanceRepository(db);
    await finance.snapshot();
    await finance.setState('security:lock_enabled', 'true');
    final prefs = LocalLockPreferences(finance);
    final legacy = await prefs.readConfiguration();
    expect(legacy.legacyDeviceLock, isTrue);
    final auth = FakeBiometrics();
    final lock = AppLock(prefs, auth, passwordHasher: FakePasswordHasher());
    addTearDown(lock.dispose);
    await lock.initialize();
    expect(await lock.unlock(), isTrue);
    expect(await lock.setPassword('Password!123'), isTrue);
    expect(await lock.configure(false, password: 'Password!123'), isTrue);
    final saved = await LocalLockPreferences(finance).readConfiguration();
    expect(saved.biometricEnabled, isFalse);
    expect(saved.passwordRecord, isNotNull);
    await finance.setState('security:lock_configuration', '{broken');
    final corrupt = AppLock(prefs, auth, passwordHasher: FakePasswordHasher());
    addTearDown(corrupt.dispose);
    await corrupt.initialize();
    expect(corrupt.ready, isFalse);
    expect(corrupt.locked, isTrue);
  });
}
