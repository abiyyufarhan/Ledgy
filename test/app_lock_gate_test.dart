import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/security/domain/app_lock.dart';
import 'package:ledgy/features/security/presentation/app_lock_gate.dart';
import 'package:ledgy/features/security/presentation/lock_providers.dart';

class _Preferences implements LockPreferences {
  @override
  Future<bool> enabled() async => true;
  @override
  Future<void> setEnabled(bool value) async {}
}

class _Authenticator implements DeviceAuthenticator {
  bool accepted = false;
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> authenticate() async => accepted;
}

void main() {
  testWidgets('ledger hidden at startup, cancellation, background and resume', (
    tester,
  ) async {
    final auth = _Authenticator();
    final lock = AppLock(_Preferences(), auth);
    addTearDown(lock.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLockProvider.overrideWithValue(lock)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const AppLockGate(
            child: Scaffold(body: Text('PRIVATE LEDGER')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE LEDGER'), findsNothing);
    await tester.tap(find.text('Buka Ledgy'));
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE LEDGER'), findsNothing);
    auth.accepted = true;
    await tester.tap(find.text('Buka Ledgy'));
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE LEDGER'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('PRIVATE LEDGER'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE LEDGER'), findsNothing);
    await tester.tap(find.text('Buka Ledgy'));
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE LEDGER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
