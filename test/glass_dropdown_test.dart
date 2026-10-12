import 'dart:io';
import 'dart:ui' show PointerDeviceKind, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/app_backdrop.dart';
import 'package:ledgy/core/widgets/expanding_glass_button.dart';
import 'package:ledgy/core/widgets/glass_dropdown_field.dart';
import 'package:ledgy/core/widgets/glass_menu.dart';
import 'package:ledgy/features/auth/domain/auth_repository.dart';
import 'package:ledgy/features/auth/presentation/profile_menu.dart';
import 'package:ledgy/features/sync/presentation/sync_providers.dart';

class _LocalAuth implements AuthRepository {
  @override
  bool get configured => false;
  @override
  CloudUser? get currentUser => null;
  @override
  Stream<CloudUser?> get changes => const Stream.empty();
  @override
  Future<bool> signUp(
    String email,
    String password, {
    String? name,
    SaverProfile? saverProfile,
  }) async => false;
  @override
  Future<void> updateSaverProfile(SaverProfile profile) async {}
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> resendConfirmation(String email) async {}
}

final _previewKey = GlobalKey();
Future<void> _preview(WidgetTester tester, String name) async {
  if (Platform.environment['LEDGY_VISUAL_QA'] != '1') return;
  final boundary =
      _previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final folder = Directory('build/ui-previews');
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('profil kecil tajam, posisi lega, menu glass membuka ke bawah', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 880);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        if (Platform.isWindows) {
          final text = FontLoader('Manrope')
            ..addFont(
              File('C:/Windows/Fonts/segoeui.ttf')
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes)),
            );
          await text.load();
        }
      });
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(_LocalAuth())],
        child: RepaintBoundary(
          key: _previewKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            builder: (_, child) => AppBackdrop(child: child!),
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Ledgy'),
                actions: const [ProfileMenu()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byType(ExpandingGlassButton);
    final before = tester.getRect(button);
    expect(before.size, const Size(48, 48));
    expect(before.top, greaterThanOrEqualTo(12));
    expect(
      tester.getSize(find.byIcon(Icons.person_rounded)),
      const Size(24, 24),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      tester.widget<ClipOval>(find.byType(ClipOval)).clipBehavior,
      Clip.antiAlias,
    );
    await _preview(tester, 'profile-closed-2x');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(before.center);
    await tester.pumpAndSettle();
    expect(tester.getRect(button).right, before.right);
    expect(tester.getSize(button).width, AppTheme.profileExpandedWidth);
    await _preview(tester, 'profile-hover-2x');
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final transition = tester.widget<SizeTransition>(
      find.byType(SizeTransition).last,
    );
    expect(transition.sizeFactor.value, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(find.byType(GlassMenuSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byIcon(Icons.login), findsOneWidget);
    expect(find.text('Setting'), findsOneWidget);
    expect(find.text('Exit'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    final surface = tester.getRect(find.byType(GlassMenuSurface));
    expect(surface.right, before.right);
    expect(surface.top, before.top);
    await _preview(tester, 'profile-menu-2x');
    // Tapping the header collapses the menu, and removes its blur entirely.
    await tester.tap(
      find.descendant(
        of: find.byType(GlassMenuSurface),
        matching: find.text('Daftar / Login'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlassMenuSurface), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropdown nullable: pilih, batalkan, dan kembali ke semua akun', (
    tester,
  ) async {
    String? selected = 'bank';
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: StatefulBuilder(
                builder: (_, update) => GlassDropdownFormField<String?>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Akun'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Semua akun')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank Jago')),
                    DropdownMenuItem(value: 'cash', child: Text('Tunai')),
                    DropdownMenuItem(
                      value: 'disabled',
                      enabled: false,
                      child: Text('Diarsipkan'),
                    ),
                  ],
                  onChanged: (value) => update(() {
                    selected = value;
                    changes++;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(GlassDropdownFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diarsipkan'));
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(find.byType(GlassMenuSurface), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selected, 'bank');
    expect(changes, 0);
    await tester.tap(find.byType(GlassDropdownFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tunai'));
    await tester.pumpAndSettle();
    expect(selected, 'cash');
    await tester.tap(find.byType(GlassDropdownFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semua akun'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(changes, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'menu panjang lazy, satu blur, aman di layar kecil dengan keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
              viewInsets: const EdgeInsets.only(bottom: 220),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 250,
                child: GlassDropdownFormField<String>(
                  initialValue: '0',
                  decoration: const InputDecoration(labelText: 'Aset'),
                  items: List.generate(
                    250,
                    (i) =>
                        DropdownMenuItem(value: '$i', child: Text('Aset $i')),
                  ),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GlassDropdownFormField<String>));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(GlassMenuSurface));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThanOrEqualTo(380));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Aset 249'), findsNothing);
      expect(find.byType(ListView).evaluate().length, 1);
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();
      expect(find.byType(GlassMenuSurface), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
