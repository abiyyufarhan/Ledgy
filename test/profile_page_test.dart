import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/app_backdrop.dart';
import 'package:ledgy/core/providers/platform_providers.dart';
import 'package:ledgy/features/auth/data/profile_actions.dart';
import 'package:ledgy/features/auth/domain/auth_repository.dart';
import 'package:ledgy/features/auth/presentation/profile_menu.dart';
import 'package:ledgy/features/auth/presentation/profile_page.dart';
import 'package:ledgy/features/sync/presentation/sync_providers.dart';

import 'support/profile_auth.dart';

final _previewKey = GlobalKey();
Future<ProfileTestAuth> _show(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  VoidCallback? exit,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = ProfileTestAuth();
  addTearDown(auth.events.close);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: ProfileMenu.sidebar(labels: AlwaysStoppedAnimation(1)),
            ),
          ),
        ),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        exitApplicationProvider.overrideWithValue(() async {
          exit?.call();
        }),
        profileActionsProvider.overrideWith(
          (ref) => throw StateError(
            'No destructive action should run in these widget tests.',
          ),
        ),
      ],
      child: RepaintBoundary(
        key: _previewKey,
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: AppBackdrop(child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('sidebar-profile-avatar')));
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _preview(WidgetTester tester, String name) async {
  if (Platform.environment['LEDGY_VISUAL_QA'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    await Directory('build/ui-previews').create(recursive: true);
    await File('build/ui-previews/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
      await (FontLoader('Manrope')..addFont(
            File('assets/fonts/NotoSans-Regular.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final size in [const Size(390, 960), const Size(1280, 1000)]) {
    testWidgets('kartu profil membuka Detail Akun ${size.width}px', (
      tester,
    ) async {
      await _show(tester, size);
      expect(find.text('Detail Akun'), findsOneWidget);
      expect(find.text('Informasi Akun'), findsOneWidget);
      expect(find.text('Abiyyu Farhan'), findsOneWidget);
      expect(find.text('abiy@example.com'), findsOneWidget);
      expect(find.text('Profil Penabung'), findsOneWidget);
      expect(find.text('Premium Hingga'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('profile-delete')));
      expect(find.text('Area Berbahaya'), findsOneWidget);
      expect(find.text('Reset Data'), findsOneWidget);
      expect(find.text('Hapus Akun'), findsOneWidget);
      await tester.pumpAndSettle();
      await _preview(tester, 'account-detail-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsNothing);
    });
  }
  testWidgets('nama, email dan profil penabung dapat diperbarui', (
    tester,
  ) async {
    final auth = await _show(tester, const Size(1280, 1000));
    await tester.tap(find.text('Abiyyu Farhan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' Nama Baru ');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(auth.currentUser!.displayName, 'Nama Baru');
    expect(find.text('Nama Baru'), findsOneWidget);
    await tester.tap(find.text('abiy@example.com'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'salah');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Masukkan email yang valid.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'baru@example.com');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(auth.requestedEmail, 'baru@example.com');
    expect(find.text('abiy@example.com'), findsOneWidget);
    expect(find.textContaining('tautan konfirmasi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-saver-row')));
    await tester.pumpAndSettle();
    await _preview(tester, 'account-saver-choices');
    await tester.tap(find.byKey(const ValueKey('saver-choice-aggressive')));
    await tester.pumpAndSettle();
    expect(auth.currentUser!.saverProfile, SaverProfile.aggressive);
    expect(find.text(SaverProfile.aggressive.label), findsOneWidget);
  });
  testWidgets('perubahan gagal tetap mempertahankan profil lama', (
    tester,
  ) async {
    final auth = await _show(tester, const Size(1280, 1000));
    auth.failure = 'Tidak ada koneksi internet.';
    await tester.tap(find.byKey(const ValueKey('profile-saver-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saver-choice-aggressive')));
    await tester.pumpAndSettle();
    expect(auth.currentUser!.saverProfile, SaverProfile.moderate);
    expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
  });
  testWidgets(
    'reset dan hapus membutuhkan konfirmasi; batal tidak mengubah data',
    (tester) async {
      final auth = await _show(tester, const Size(390, 960));
      await tester.ensureVisible(find.byKey(const ValueKey('profile-reset')));
      await tester.tap(find.byKey(const ValueKey('profile-reset')));
      await tester.pumpAndSettle();
      expect(find.text('Reset Data?'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('profile-delete')));
      await tester.tap(find.byKey(const ValueKey('profile-delete')));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'Hapus Akun');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'HAPUS');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(auth.deletions, 0);
      expect(auth.currentUser, isNotNull);
    },
  );
  testWidgets('keluar menutup aplikasi dan font besar tetap dapat digulir', (
    tester,
  ) async {
    var exits = 0;
    await _show(tester, const Size(390, 960), scale: 2, exit: () => exits++);
    await tester.ensureVisible(find.text('Keluar'));
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(exits, 1);
    await tester.ensureVisible(find.byKey(const ValueKey('profile-delete')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
