import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind, ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/app/ledgy_app.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/core/providers/platform_providers.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/expanding_glass_button.dart';
import 'package:ledgy/core/widgets/ledgy_sidebar.dart';
import 'package:ledgy/features/auth/domain/auth_repository.dart';
import 'package:ledgy/features/auth/presentation/profile_menu.dart';
import 'package:ledgy/features/auth/presentation/saver_profile_widgets.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/local/presentation/local_providers.dart';
import 'package:ledgy/features/sync/domain/sync_models.dart';
import 'package:ledgy/features/sync/presentation/sync_providers.dart';
import 'package:ledgy/features/security/presentation/lock_providers.dart';

import 'support/unlocked_app.dart';

final _budgetPreviewKey = GlobalKey();

Future<void> _budgetPreview(WidgetTester tester, String name) async {
  if (Platform.environment['LEDGY_VISUAL_QA'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_budgetPreviewKey),
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
    await File('build/ui-previews/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _Auth implements AuthRepository {
  @override
  bool get configured => true;
  @override
  CloudUser? currentUser;
  final events = StreamController<CloudUser?>.broadcast();
  bool confirmEmail = false;
  String? signupName;
  SaverProfile? signupProfile;
  String? profileError;
  @override
  Stream<CloudUser?> get changes => events.stream;
  @override
  Future<bool> signUp(
    String email,
    String password, {
    String? name,
    SaverProfile? saverProfile,
  }) async {
    signupName = name;
    signupProfile = saverProfile;
    if (confirmEmail) return false;
    currentUser = CloudUser(
      'user',
      email,
      name: name,
      saverProfile: saverProfile,
    );
    events.add(currentUser);
    return true;
  }

  @override
  Future<void> signIn(String email, String password) async {
    currentUser = CloudUser(
      'user',
      email,
      name: signupName,
      saverProfile: signupProfile,
    );
    events.add(currentUser);
  }

  @override
  Future<void> resendConfirmation(String email) async {}
  @override
  Future<void> updateSaverProfile(SaverProfile profile) async {
    if (profileError != null) throw AuthFailure(profileError!);
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
  Future<void> signOut() async {
    currentUser = null;
    events.add(null);
  }
}

Future<AppDatabase> _show(
  WidgetTester tester,
  _Auth auth,
  String route,
  Size size, {
  Future<void> Function()? onExit,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(auth.events.close);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = LocalFinanceRepository(db);
  final snapshot = await repo.snapshot();
  if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('Manrope')..addFont(
            File('C:/Windows/Fonts/segoeui.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appLockProvider.overrideWith((ref) => unlockedTestApp()),
        databaseProvider.overrideWithValue(db),
        exitApplicationProvider.overrideWithValue(onExit ?? () async {}),
        authRepositoryProvider.overrideWithValue(auth),
        accountsProvider.overrideWith((ref) => Stream.value(snapshot.accounts)),
        categoriesProvider.overrideWith(
          (ref) => Stream.value(snapshot.categories),
        ),
        transactionsProvider.overrideWith((ref) => Stream.value([])),
        budgetsProvider.overrideWith((ref) => Stream.value([])),
        financeSnapshotProvider.overrideWith((ref) async => snapshot),
        syncQueueProvider.overrideWith(
          (ref) => Stream.value(const SyncQueue(0, 0)),
        ),
        syncStatusProvider.overrideWith(
          (ref) => Stream.value(const SyncStatus()),
        ),
      ],
      child: RepaintBoundary(
        key: _budgetPreviewKey,
        child: LedgyApp(initialLocation: route),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<void> _fillSignup(WidgetTester tester) async {
  for (final (label, value) in [
    ('Nama profil', 'Abiy'),
    ('Email', 'abiy@example.com'),
    ('Kata sandi', 'password123'),
    ('Ulangi kata sandi', 'password123'),
  ]) {
    await tester.ensureVisible(find.widgetWithText(TextFormField, label));
    await tester.enterText(find.widgetWithText(TextFormField, label), value);
  }
  await tester.ensureVisible(
    find.byKey(const ValueKey('saver-choice-moderate')),
  );
  await tester.tap(find.byKey(const ValueKey('saver-choice-moderate')));
  await tester.ensureVisible(find.text('Daftar akun'));
  await tester.tap(find.text('Daftar akun'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('Exit Android menutup activity melalui SystemNavigator', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(exitApplicationProvider)();
    expect(calls, ['SystemNavigator.pop']);
  });

  testWidgets('hover melebar ke kiri dan avatar/printer tetap di kanan', (
    tester,
  ) async {
    for (final size in [AppTheme.profileButtonSize, AppTheme.printButtonSize]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: ExpandingGlassButton(
                key: ValueKey(size),
                label: 'Abiy',
                size: size,
                expandedWidth: 200,
                trailing: const Icon(Icons.print_outlined),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byType(ExpandingGlassButton);
      final before = tester.getRect(button);
      final iconBefore = tester.getCenter(find.byIcon(Icons.print_outlined));
      expect(before.width, size);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(before.center);
      await tester.pumpAndSettle();
      final after = tester.getRect(button);
      expect(after.width, 200);
      expect(after.right, before.right);
      expect(tester.getCenter(find.byIcon(Icons.print_outlined)), iconBefore);
      await mouse.moveTo(const Offset(10, 500));
      await tester.pumpAndSettle();
      expect(tester.getRect(button).width, size);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    }
  });

  for (final size in [const Size(360, 800), const Size(1280, 600)]) {
    testWidgets(
      'Anggaran dan Dashboard melalui navigasi ${size.width.toInt()}px',
      (tester) async {
        await _show(tester, _Auth(), '/budget', size);
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.more_vert), findsNothing);
        expect(
          find.textContaining('Belum ada anggaran untuk bulan ini'),
          findsNothing,
        );
        expect(find.text('Tambah anggaran'), findsNothing);
        expect(find.text('Aktifkan notifikasi'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('budget-actions-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Tambah anggaran'), findsOneWidget);
        expect(find.text('Aktifkan notifikasi'), findsOneWidget);
        await _budgetPreview(tester, 'budget-actions-${size.width.toInt()}');
        await tester.tap(find.text('Tambah anggaran'));
        await tester.pumpAndSettle();
        expect(find.text('Anggaran baru'), findsOneWidget);
        await tester.tap(find.text('Simpan'));
        await tester.pumpAndSettle();
        expect(
          find.text('Pilih kategori dan isi nominal lebih dari nol.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Batal'));
        await tester.pumpAndSettle();
        if (size.width >= AppTheme.sidebarBreakpoint) {
          await tester.tapAt(const Offset(32, 32));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('sidebar-destination-/budget')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Anggaran Bulanan'), findsNothing);
          await _budgetPreview(tester, 'budget-sidebar-closed');
          await tester.tap(
            find.byKey(const ValueKey('sidebar-destination-/budget')),
          );
          await tester.pumpAndSettle();
          await _budgetPreview(tester, 'budget-sidebar-open');
        } else {
          await tester.tap(find.byKey(const ValueKey('budget-section-menu')));
          await tester.pumpAndSettle();
        }
        expect(find.text('Anggaran Bulanan'), findsOneWidget);
        expect(find.text('Transaksi Berulang'), findsOneWidget);
        final nav = size.width >= 700
            ? find.byType(LedgySidebar)
            : find.byType(NavigationBar);
        if (size.width >= 700) {
          final labels = tester
              .widget<LedgySidebar>(nav)
              .destinations
              .map((d) => d.label);
          expect(labels, [
            'Dashboard',
            'Transaksi',
            'Anggaran',
            'Aset',
            'Setting',
          ]);
          expect(
            tester.widget<LedgySidebar>(nav).destinations.last.icon,
            Icons.settings_outlined,
          );
        }
        await tester.tap(find.text('Transaksi Berulang'));
        await tester.pumpAndSettle();
        expect(find.text('Tambah jadwal'), findsOneWidget);
        expect(find.byKey(const ValueKey('budget-actions-menu')), findsNothing);
        if (size.width >= AppTheme.sidebarBreakpoint) {
          expect(tester.widget<LedgySidebar>(nav).selectedIndex, 2);
          expect(
            tester.widget<LedgySidebar>(nav).selectedSubpath,
            '/budget?section=recurring',
          );
        }
        await _budgetPreview(tester, 'budget-recurring-${size.width.toInt()}');
        if (size.width < AppTheme.sidebarBreakpoint) {
          await tester.tap(find.byKey(const ValueKey('budget-section-menu')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Anggaran Bulanan'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('budget-actions-menu')),
          findsOneWidget,
        );
        expect(find.text('Tambah jadwal'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('csv-print-button')));
        await tester.pumpAndSettle();
        expect(find.text('Pilih CSV'), findsOneWidget);
        await tester.tap(
          size.width >= AppTheme.sidebarBreakpoint
              ? find.byKey(const ValueKey('sidebar-destination-/'))
              : find.descendant(of: nav, matching: find.text('Dashboard')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Tren Arus Kas'), findsOneWidget);
        expect(find.text('Analisis'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final confirmEmail in [false, true]) {
    testWidgets('Profil → daftar → aset; konfirmasi email $confirmEmail', (
      tester,
    ) async {
      final auth = _Auth()..confirmEmail = confirmEmail;
      final db = await _show(tester, auth, '/budget', const Size(1280, 900));
      await tester.tap(find.byKey(const ValueKey('sidebar-profile-avatar')));
      await tester.pumpAndSettle();
      expect(find.text('Detail Akun'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('profile-login')));
      await tester.tap(find.byKey(const ValueKey('profile-login')));
      await tester.pumpAndSettle();
      expect(find.text('Nama profil'), findsOneWidget);
      await _fillSignup(tester);
      expect(auth.signupName, 'Abiy');
      expect(auth.signupProfile, SaverProfile.moderate);
      if (confirmEmail) {
        expect(find.text('Nama tempat aset'), findsNothing);
        expect(
          find.textContaining('email konfirmasi telah dikirim'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Masuk dan sinkronkan'));
        await tester.tap(find.text('Masuk dan sinkronkan'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Nama tempat aset'), findsOneWidget);
      await tester.tap(find.text('Simpan aset'));
      await tester.pumpAndSettle();
      expect(find.text('Masukkan nama aset.'), findsOneWidget);
      final before = await db.select(db.accounts).get();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama tempat aset'),
        ' Bank Baru ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Saldo awal (Rp)'),
        '3000000000',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Simpan aset'));
        // Wait for the real SQLite write and navigation, not an arbitrary timer.
        await db.accountsDao.watchActive().firstWhere(
          (rows) => rows.length == before.length + 1,
        );
      });
      await tester.pumpAndSettle();
      final after = await db.select(db.accounts).get();
      expect(after.length, before.length + 1);
      expect(after.last.name, 'Bank Baru');
      expect(after.last.initialBalance, 3000000000);
      expect(find.text('Simpan aset'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Detail Akun, keluar, dan navigasi pengaturan tetap berfungsi', (
    tester,
  ) async {
    var exits = 0;
    await _show(
      tester,
      _Auth(),
      '/budget',
      const Size(1280, 900),
      onExit: () async {
        exits++;
      },
    );
    await tester.tap(find.byKey(const ValueKey('sidebar-profile-avatar')));
    await tester.pumpAndSettle();
    expect(find.text('Detail Akun'), findsOneWidget);
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(exits, 1);
    await tester.tap(find.byKey(const ValueKey('sidebar-icon-/settings')));
    await tester.pumpAndSettle();
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'profil tidak ada di Setting dan perubahan Detail Akun memperbarui sidebar',
    (tester) async {
      final auth = _Auth()
        ..currentUser = const CloudUser(
          'a',
          'a@example.com',
          name: 'Nama A',
          saverProfile: SaverProfile.moderate,
        );
      await _show(tester, auth, '/budget', const Size(1280, 900));
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(ProfileMenu),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<SaverProfileBadge>(find.byType(SaverProfileBadge))
            .profile,
        SaverProfile.moderate,
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-icon-/settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SaverProfileField), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar-profile-avatar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-saver-row')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('saver-choice-aggressive')),
      );
      await tester.tap(find.byKey(const ValueKey('saver-choice-aggressive')));
      await tester.pumpAndSettle();
      expect(auth.currentUser?.saverProfile, SaverProfile.aggressive);
      expect(
        tester
            .widget<SaverProfileBadge>(find.byType(SaverProfileBadge))
            .profile,
        SaverProfile.aggressive,
      );
      auth.currentUser = const CloudUser(
        'b',
        'b@example.com',
        name: 'Nama B',
        saverProfile: SaverProfile.conservative,
      );
      auth.events.add(auth.currentUser);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SaverProfileBadge>(find.byType(SaverProfileBadge))
            .profile,
        SaverProfile.conservative,
      );
      expect(find.text('Nama A'), findsNothing);
      auth.currentUser = null;
      auth.events.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(SaverProfileBadge), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'perubahan profil yang gagal mempertahankan pilihan terakhir tersimpan',
    (tester) async {
      final auth = _Auth()
        ..currentUser = const CloudUser(
          'a',
          'a@example.com',
          saverProfile: SaverProfile.moderate,
        )
        ..profileError = 'Tidak ada koneksi internet. Coba lagi.';
      await _show(tester, auth, '/profile', const Size(1280, 900));
      await tester.tap(find.byKey(const ValueKey('profile-saver-row')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('saver-choice-aggressive')),
      );
      await tester.tap(find.byKey(const ValueKey('saver-choice-aggressive')));
      await tester.pumpAndSettle();
      expect(
        find.text('Tidak ada koneksi internet. Coba lagi.'),
        findsOneWidget,
      );
      expect(auth.currentUser?.saverProfile, SaverProfile.moderate);
      expect(
        tester
            .widget<SaverProfileBadge>(find.byType(SaverProfileBadge))
            .profile,
        SaverProfile.moderate,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
