import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/security/domain/app_lock.dart';

class Preferences implements LockPreferences {
  Preferences(this.value);
  bool value;
  bool fail = false;
  Completer<void>? pendingWrite;
  @override
  Future<bool> enabled() async {
    if (fail) throw StateError('private');
    return value;
  }

  @override
  Future<void> setEnabled(bool value) async {
    if (pendingWrite != null) await pendingWrite!.future;
    this.value = value;
  }
}

class Authenticator implements DeviceAuthenticator {
  bool supported = true;
  bool accepted = true;
  Completer<bool>? pending;
  @override
  Future<bool> available() async => supported;
  @override
  Future<bool> authenticate() async =>
      pending == null ? accepted : pending!.future;
}

void main() {
  test(
    'background during preference write keeps newly enabled lock closed',
    () async {
      final preferences = Preferences(false)..pendingWrite = Completer<void>();
      final lock = AppLock(preferences, Authenticator());
      addTearDown(lock.dispose);
      await lock.initialize();
      final configuring = lock.configure(true);
      await Future<void>.delayed(Duration.zero);
      lock.background();
      lock.resume();
      preferences.pendingWrite!.complete();
      expect(await configuring, isFalse);
      expect(lock.enabled, isTrue);
      expect(lock.locked, isTrue);
    },
  );
  test('startup fails closed, cancellation stays locked, resume requires authentication', () async {
    final auth = Authenticator();
    final lock = AppLock(Preferences(true), auth);
    addTearDown(lock.dispose);
    expect(lock.locked, isTrue);
    await lock.initialize();
    auth.accepted = false;
    expect(await lock.unlock(), isFalse);
    expect(lock.locked, isTrue);
    auth.accepted = true;
    expect(await lock.unlock(), isTrue);
    lock.background();
    lock.resume();
    expect(lock.locked, isTrue);
    expect(await lock.unlock(), isTrue);
  });
  test(
    'authentication finishing after background cannot unlock data',
    () async {
      final auth = Authenticator()..pending = Completer<bool>();
      final lock = AppLock(Preferences(true), auth);
      addTearDown(lock.dispose);
      await lock.initialize();
      final pending = lock.unlock();
      lock.background();
      lock.resume();
      auth.pending!.complete(true);
      expect(await pending, isFalse);
      expect(lock.locked, isTrue);
    },
  );
  test('settings require verification and persist across restart', () async {
    final preferences = Preferences(false);
    final auth = Authenticator()..accepted = false;
    final lock = AppLock(preferences, auth);
    addTearDown(lock.dispose);
    await lock.initialize();
    expect(await lock.configure(true), isFalse);
    expect(preferences.value, isFalse);
    auth.accepted = true;
    expect(await lock.configure(true), isTrue);
    final restarted = AppLock(preferences, Authenticator());
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(restarted.locked, isTrue);
    expect(await restarted.unlock(), isTrue);
    expect(await restarted.configure(false), isTrue);
    expect(preferences.value, isFalse);
  });
  test('unreadable preference never exposes ledger', () async {
    final lock = AppLock(Preferences(false)..fail = true, Authenticator());
    addTearDown(lock.dispose);
    await lock.initialize();
    expect(lock.ready, isFalse);
    expect(lock.locked, isTrue);
    expect(lock.error, isNot(contains('private')));
  });
}
