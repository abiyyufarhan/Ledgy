import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local/presentation/local_providers.dart';
import '../data/lock_repository.dart';
import '../data/password_hasher.dart';
import '../domain/app_lock.dart';

final appLockProvider = Provider<AppLock>((ref) {
  final lock = AppLock(
    LocalLockPreferences(ref.watch(localFinanceProvider)),
    LocalDeviceAuthenticator(),
    passwordHasher: Pbkdf2PasswordHasher(),
  );
  ref.onDispose(() => unawaited(lock.dispose()));
  return lock;
});

final appLockChangesProvider = StreamProvider<int>(
  (ref) => ref.watch(appLockProvider).changes,
);
