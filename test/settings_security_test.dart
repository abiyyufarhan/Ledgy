import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/app/ledgy_app.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/auth/presentation/saver_profile_widgets.dart';
import 'package:ledgy/features/security/data/lock_repository.dart';
import 'package:ledgy/features/security/domain/app_lock.dart';
import 'package:ledgy/features/security/presentation/app_lock_gate.dart';
import 'package:ledgy/features/security/presentation/lock_providers.dart';
import 'package:ledgy/features/security/presentation/security_settings.dart';
import 'package:ledgy/features/sync/domain/sync_models.dart';
import 'package:ledgy/features/sync/presentation/sync_providers.dart';
import 'package:local_auth/local_auth.dart';

import 'support/password_lock.dart';
import 'support/profile_auth.dart';

class _LocalAuthentication extends LocalAuthentication {
  bool supported = true;
  bool canCheck = true;
  List<BiometricType> enrolled = [];
  @override
  Future<bool> isDeviceSupported() async => supported;
  @override
  Future<bool> get canCheckBiometrics async => canCheck;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  test(
    'Windows requires real biometric hardware even when Hello supports PIN',
    () async {
      const channel = MethodChannel('com.ledgy.ledgy/biometrics');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final auth = _LocalAuthentication();
      final device = LocalDeviceAuthenticator(auth: auth, isWindows: true);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(await device.available(), isFalse);
      messenger.setMockMethodCallHandler(channel, (_) async => true);
      expect(await device.available(), isTrue);
      auth.supported = false;
      expect(await device.available(), isFalse);
      auth.supported = true;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unsupported'),
      );
      expect(await device.available(), isFalse);
      final mobile = LocalDeviceAuthenticator(auth: auth, isWindows: false);
      expect(await mobile.available(), isFalse);
      auth.enrolled = [BiometricType.fingerprint];
      expect(await mobile.available(), isTrue);
      auth.canCheck = false;
      expect(await mobile.available(), isFalse);
    },
  );

  for (final supported in [false, true]) {
    testWidgets('biometric switch checks device before enabling: $supported', (
      tester,
    ) async {
      final auth = FakeBiometrics()..pendingAvailability = Completer<bool>();
      final lock = AppLock(
        MemoryLockPreferences(),
        auth,
        passwordHasher: FakePasswordHasher(),
      );
      addTearDown(lock.dispose);
      await lock.initialize();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLockProvider.overrideWithValue(lock)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SingleChildScrollView(child: SecuritySettings()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('biometric-toggle')))
            .onChanged,
        isNull,
      );
      auth.supported = supported;
      auth.pendingAvailability!.complete(supported);
      auth.pendingAvailability = null;
      await tester.pumpAndSettle();
      final toggle = tester.widget<Switch>(
        find.byKey(const ValueKey('biometric-toggle')),
      );
      expect(toggle.onChanged != null, supported);
      if (supported) {
        await tester.tap(find.byKey(const ValueKey('biometric-toggle')));
        await tester.pumpAndSettle();
        expect(lock.biometricEnabled, isTrue);
      }
      expect(auth.prompts, supported ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'password setup validates confirmation and gate rejects wrong passwords',
    (tester) async {
      final prefs = MemoryLockPreferences();
      final lock = AppLock(
        prefs,
        FakeBiometrics(),
        passwordHasher: FakePasswordHasher(),
      );
      addTearDown(lock.dispose);
      await lock.initialize();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLockProvider.overrideWithValue(lock)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const AppLockGate(
              child: Scaffold(
                body: SingleChildScrollView(child: SecuritySettings()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('password-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password baru'),
        'AaZz019!@#',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Konfirmasi password'),
        'different',
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi password belum sama.'), findsOneWidget);
      expect(lock.passwordEnabled, isFalse);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Konfirmasi password'),
        'AaZz019!@#',
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(lock.passwordEnabled, isTrue);
      await tester.ensureVisible(find.text('Kunci sekarang'));
      await tester.tap(find.text('Kunci sekarang'));
      await tester.pumpAndSettle();
      expect(find.byType(SecuritySettings), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('unlock-password')),
        'wrong',
      );
      await tester.tap(find.byKey(const ValueKey('unlock-password-button')));
      await tester.pumpAndSettle();
      expect(lock.locked, isTrue);
      expect(find.text('Password Ledgy salah.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('unlock-password')),
        'AaZz019!@#',
      );
      await tester.tap(find.byKey(const ValueKey('unlock-password-button')));
      await tester.pumpAndSettle();
      expect(lock.locked, isFalse);
      expect(find.byType(SecuritySettings), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(lock.locked, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1280, 940), const Size(360, 900)]) {
    testWidgets(
      'settings uses flat rows, no saver selector, and compact sync at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = ProfileTestAuth();
        addTearDown(auth.events.close);
        final lock = AppLock(
          MemoryLockPreferences(),
          FakeBiometrics(),
          passwordHasher: FakePasswordHasher(),
        );
        addTearDown(lock.dispose);
        final preview = GlobalKey();
        if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
          await tester.runAsync(() async {
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
            await (FontLoader('Manrope')..addFont(
                  rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
                ))
                .load();
          });
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appLockProvider.overrideWithValue(lock),
              authRepositoryProvider.overrideWithValue(auth),
              syncStatusProvider.overrideWith(
                (ref) => Stream.value(
                  const SyncStatus(
                    phase: SyncPhase.synced,
                    message: 'Seluruh perubahan sudah tersimpan.',
                  ),
                ),
              ),
              syncQueueProvider.overrideWith(
                (ref) => Stream.value(const SyncQueue(0, 0)),
              ),
            ],
            child: RepaintBoundary(
              key: preview,
              child: LedgyApp(initialLocation: '/settings'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SaverProfileField), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byKey(const ValueKey('sync-now')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('sync-now'))).width,
          lessThanOrEqualTo(56),
        );
        expect(find.byTooltip('Sinkronkan sekarang'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(preview),
          );
          void repaint(RenderObject object) {
            object.markNeedsPaint();
            object.visitChildren(repaint);
          }

          repaint(boundary);
          await tester.pump();
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await Directory('build/ui-previews').create(recursive: true);
            await File('build/ui-previews/settings-${size.width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
