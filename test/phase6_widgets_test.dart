import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/app/ledgy_app.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/features/dashboard/presentation/dashboard_page.dart';
import 'package:ledgy/features/dashboard/data/savings_goal_repository.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/local/presentation/local_providers.dart';
import 'package:ledgy/features/auth/data/cloud_connection.dart';
import 'package:ledgy/features/auth/domain/auth_repository.dart';
import 'package:ledgy/features/sync/domain/sync_models.dart';
import 'package:ledgy/features/sync/presentation/sync_providers.dart';
import 'package:ledgy/features/security/presentation/lock_providers.dart';

import 'support/unlocked_app.dart';

class _Auth implements AuthRepository {
  _Auth({this.configured = true});
  @override
  final bool configured;
  @override
  CloudUser? currentUser;
  final events = StreamController<CloudUser?>.broadcast();
  @override
  Stream<CloudUser?> get changes => events.stream;
  String? error;
  bool activateSignup = false;
  int signups = 0;
  @override
  Future<void> signIn(String email, String password) async {
    if (error != null) throw AuthFailure(error!);
    currentUser = CloudUser('user', email);
    events.add(currentUser);
  }

  @override
  Future<bool> signUp(
    String email,
    String password, {
    String? name,
    SaverProfile? saverProfile,
  }) async {
    signups++;
    if (activateSignup) {
      currentUser = CloudUser(
        'user',
        email,
        name: name,
        saverProfile: saverProfile,
      );
      events.add(currentUser);
    }
    return activateSignup;
  }

  @override
  Future<void> updateSaverProfile(SaverProfile profile) async {
    final user = currentUser!;
    currentUser = CloudUser(
      user.id,
      user.email,
      name: user.name,
      saverProfile: profile,
    );
    events.add(currentUser);
  }

  @override
  Future<void> resendConfirmation(String email) async {}
  @override
  Future<void> signOut() async {
    currentUser = null;
    events.add(null);
  }
}

class _EmptySavingsGoals extends SavingsGoals {
  @override
  Future<List<SavingsGoal>> build() async => [];
}

Future<void> _show(
  WidgetTester tester,
  _Auth auth,
  String route, {
  SyncStatus status = const SyncStatus(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appLockProvider.overrideWith((ref) => unlockedTestApp()),
        authRepositoryProvider.overrideWithValue(auth),
        syncQueueProvider.overrideWith(
          (ref) => Stream.value(SyncQueue(status.pending, 0)),
        ),
        syncStatusProvider.overrideWith((ref) => Stream.value(status)),
        accountsProvider.overrideWith((ref) => Stream.value([])),
        transactionsProvider.overrideWith((ref) => Stream.value([])),
        financeSnapshotProvider.overrideWith(
          (ref) async => const FinanceSnapshot([], [], [], [], []),
        ),
        savingsGoalsProvider.overrideWith(_EmptySavingsGoals.new),
      ],
      child: LedgyApp(initialLocation: route),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  for (final width in [400.0, 1280.0]) {
    testWidgets(
      'login glass responsif ${width.toInt()}px dan mode lokal tetap terbuka',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = _Auth(configured: false);
        addTearDown(auth.events.close);
        await _show(tester, auth, '/login');
        expect(tester.takeException(), isNull);
        final submit = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Masuk dan sinkronkan'),
        );
        expect(submit.onPressed, isNull);
        await tester.ensureVisible(find.text('Lanjut dalam mode lokal'));
        await tester.tap(find.text('Lanjut dalam mode lokal'));
        await tester.pumpAndSettle();
        expect(find.byType(DashboardPage), findsOneWidget);
      },
    );
    testWidgets(
      'Pengaturan responsif ${width.toInt()}px menampilkan antrean dan status gagal',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = _Auth()
          ..currentUser = const CloudUser('user', 'user@example.com');
        addTearDown(auth.events.close);
        await _show(
          tester,
          auth,
          '/settings',
          status: const SyncStatus(
            phase: SyncPhase.failed,
            pending: 3,
            message: 'Periksa koneksi lalu coba lagi.',
          ),
        );
        expect(find.text('Gagal'), findsOneWidget);
        expect(find.text('3 perubahan menunggu'), findsOneWidget);
        expect(find.byTooltip('Sinkronkan sekarang'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('login gagal dapat dicoba kembali dengan pesan yang jelas', (
    tester,
  ) async {
    final auth = _Auth()..error = 'Email atau kata sandi salah.';
    addTearDown(auth.events.close);
    await _show(tester, auth, '/login');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'user@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kata sandi'),
      'password123',
    );
    await tester.ensureVisible(find.text('Masuk dan sinkronkan'));
    await tester.tap(find.text('Masuk dan sinkronkan'));
    await tester.pumpAndSettle();
    expect(find.text('Email atau kata sandi salah.'), findsOneWidget);
    expect(auth.currentUser, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Masuk dan sinkronkan'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('daftar menunggu konfirmasi tidak dianggap sebagai sesi masuk', (
    tester,
  ) async {
    final auth = _Auth();
    addTearDown(auth.events.close);
    await _show(tester, auth, '/login');
    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'user@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kata sandi'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ulangi kata sandi'),
      'password123',
    );
    await tester.ensureVisible(find.text('Daftar akun'));
    await tester.tap(find.text('Daftar akun'));
    await tester.pumpAndSettle();
    expect(auth.signups, 0);
    expect(find.text('Pilih profil penabung Anda.'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('saver-choice-moderate')),
    );
    await tester.tap(find.byKey(const ValueKey('saver-choice-moderate')));
    await tester.ensureVisible(find.text('Daftar akun'));
    await tester.tap(find.text('Daftar akun'));
    await tester.pumpAndSettle();
    expect(auth.signups, 1);
    expect(auth.currentUser, isNull);
    expect(
      find.textContaining('email konfirmasi telah dikirim'),
      findsOneWidget,
    );
    expect(find.text('Kirim ulang konfirmasi email'), findsOneWidget);
  });
  testWidgets(
    'Pengaturan tanpa login menampilkan mode lokal dan ajakan masuk',
    (tester) async {
      final auth = _Auth(configured: false);
      addTearDown(auth.events.close);
      await _show(tester, auth, '/settings');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('sync-status'))).data,
        'Mode lokal',
      );
      expect(find.text('Masuk / daftar untuk sinkron'), findsOneWidget);
      expect(find.byTooltip('Sinkronkan sekarang'), findsNothing);
    },
  );
  test('konfigurasi klien menolak service_role dan secret key', () {
    String jwt(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role}))).replaceAll('=', '')}.signature';
    const url = 'https://example.supabase.co';
    expect(CloudConfig(url: url, publicKey: jwt('anon')).valid, isTrue);
    expect(
      CloudConfig(url: url, publicKey: jwt('service_role')).valid,
      isFalse,
    );
    expect(
      const CloudConfig(url: url, publicKey: 'sb_secret_secret').valid,
      isFalse,
    );
    expect(
      const CloudConfig(url: url, publicKey: 'sb_publishable_public').valid,
      isTrue,
    );
    expect(const CloudConfig.fromEnvironment().provided, isFalse);
  });
}
