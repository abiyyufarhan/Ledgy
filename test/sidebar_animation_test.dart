import 'dart:io';
import 'dart:ui' show PointerDeviceKind, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/ledgy_sidebar.dart';
import 'package:ledgy/router/app_router.dart';
import 'package:ledgy/features/auth/domain/auth_repository.dart';
import 'package:ledgy/features/sync/presentation/sync_providers.dart';

const _surface = ValueKey('sidebar-surface');
const _page = ValueKey('sidebar-page-content');
const _homeIcon = ValueKey('sidebar-icon-/');
final _previewKey = GlobalKey();

Future<void> _preview(WidgetTester tester, String name) async {
  if (Platform.environment['LEDGY_VISUAL_QA'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(LedgySidebar),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  // Flush all cached sublayers before an offscreen test capture.
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  repaint(boundary);
  await tester.pump();
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

Future<void> _shell(
  WidgetTester tester, {
  bool reducedMotion = false,
  double fontScale = 1,
  Size size = const Size(1000, 640),
  CloudUser? user,
  Widget? home,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
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
      overrides: [cloudUserProvider.overrideWith((ref) => Stream.value(user))],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(fontScale),
          ),
          child: RepaintBoundary(key: _previewKey, child: child!),
        ),
        home:
            home ??
            const AppShell(
              location: '/',
              child: SizedBox.expand(
                child: ColoredBox(color: Color(0xFF07111F)),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'ikon submenu tetap terlihat dan dapat diklik saat sidebar diminimalkan',
    (tester) async {
      final selections = <String>[];
      await _shell(
        tester,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: LedgySidebar(
              destinations: const [
                SidebarDestination(
                  '/budget',
                  'Anggaran',
                  Icons.calendar_month_outlined,
                  children: [
                    SidebarSubdestination(
                      '/budget',
                      'Anggaran Bulanan',
                      Icons.calendar_month_outlined,
                    ),
                    SidebarSubdestination(
                      '/budget?section=recurring',
                      'Transaksi Berulang',
                      Icons.autorenew,
                    ),
                  ],
                ),
              ],
              selectedIndex: 0,
              selectedSubpath: '/budget',
              onSelected: (_) {},
              onSubSelected: selections.add,
              onAddTransaction: () {},
            ),
          ),
        ),
      );
      final surface = find.byKey(_surface);
      final primary = find.byKey(const ValueKey('sidebar-icon-/budget'));
      final monthly = find.byKey(const ValueKey('sidebar-subicon-/budget'));
      final recurring = find.byKey(
        const ValueKey('sidebar-subicon-/budget?section=recurring'),
      );
      final recurringButton = find.byKey(
        const ValueKey('sidebar-subdestination-/budget?section=recurring'),
      );
      expect(tester.getSize(surface).width, AppTheme.sidebarCompactWidth);
      for (final icon in [monthly, recurring]) {
        expect(icon.hitTestable(), findsOneWidget);
        expect(tester.getCenter(icon).dx, tester.getCenter(primary).dx);
        expect(
          tester.getSize(icon).width,
          lessThan(tester.getSize(primary).width),
        );
      }
      expect(tester.getSize(recurringButton), const Size(48, 48));
      await _preview(tester, 'budget-submenu-compact-icons');
      await tester.tap(recurringButton);
      await tester.pumpAndSettle();
      expect(selections, ['/budget?section=recurring']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final compactCenter = tester.getCenter(recurring);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 300));
      await mouse.moveTo(tester.getCenter(primary));
      await tester.pumpAndSettle();
      expect(tester.getSize(surface).width, AppTheme.sidebarExpandedWidth);
      expect(tester.getCenter(recurring).dy, compactCenter.dy);
      await _preview(tester, 'budget-submenu-expanded-icons');
      await mouse.moveTo(const Offset(600, 300));
      await tester.pump(AppTheme.sidebarExitDelay);
      await tester.pumpAndSettle();
      expect(tester.getSize(surface).width, AppTheme.sidebarCompactWidth);
      expect(tester.getCenter(recurring), compactCenter);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hover halus: ikon dan layout konten tidak bergeser', (
    tester,
  ) async {
    await _shell(
      tester,
      user: const CloudUser(
        'preview',
        'nama@example.com',
        name: 'Nama',
        saverProfile: SaverProfile.moderate,
      ),
    );
    final surface = find.byKey(_surface);
    final initialPage = tester.getRect(find.byKey(_page));
    final initialIcon = tester.getCenter(find.byKey(_homeIcon));
    expect(tester.getSize(surface).width, AppTheme.sidebarCompactWidth);
    expect(initialIcon.dx, 32);
    expect(initialPage.left, 65);
    expect(find.byType(BackdropFilter), findsNothing);
    await _preview(tester, 'sidebar-compact');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 300));
    await mouse.moveTo(initialIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester.getSize(surface).width,
      inExclusiveRange(
        AppTheme.sidebarCompactWidth,
        AppTheme.sidebarExpandedWidth,
      ),
    );
    expect(tester.getCenter(find.byKey(_homeIcon)), initialIcon);
    expect(tester.getRect(find.byKey(_page)), initialPage);
    await _preview(tester, 'sidebar-midpoint');
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).width, AppTheme.sidebarExpandedWidth);
    expect(tester.getRect(find.byKey(_page)), initialPage);
    await _preview(tester, 'sidebar-expanded');
    final transaction = find.byKey(
      const ValueKey('sidebar-transaction-surface'),
    );
    final plus = find.descendant(of: transaction, matching: find.byType(Stack));
    final plusCenter = tester.getCenter(plus);
    expect(tester.getSize(transaction).width, AppTheme.minTouchTarget);
    await mouse.moveTo(plusCenter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester.getSize(transaction).width,
      inExclusiveRange(
        AppTheme.minTouchTarget,
        AppTheme.sidebarExpandedWidth - AppTheme.compactSpacing * 2,
      ),
    );
    expect(tester.getCenter(plus), plusCenter);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(transaction).width,
      AppTheme.sidebarExpandedWidth - AppTheme.compactSpacing * 2,
    );
    expect(tester.getRect(find.byKey(_page)), initialPage);
    await _preview(tester, 'sidebar-transaction-expanded');
    await mouse.moveTo(initialIcon);
    await tester.pumpAndSettle();
    expect(tester.getSize(transaction).width, AppTheme.minTouchTarget);

    // A short exit does not collapse the surface; re-entry cancels that timer.
    await mouse.moveTo(const Offset(600, 300));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(surface).width, AppTheme.sidebarExpandedWidth);
    await mouse.moveTo(initialIcon);
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.getSize(surface).width, AppTheme.sidebarExpandedWidth);

    // Reverse a collapse in flight without resetting its progress.
    await mouse.moveTo(const Offset(600, 300));
    await tester.pump(AppTheme.sidebarExitDelay);
    await tester.pump(const Duration(milliseconds: 80));
    final reversingWidth = tester.getSize(surface).width;
    expect(
      reversingWidth,
      inExclusiveRange(
        AppTheme.sidebarCompactWidth,
        AppTheme.sidebarExpandedWidth,
      ),
    );
    await mouse.moveTo(initialIcon);
    await tester.pump();
    expect(tester.getSize(surface).width, closeTo(reversingWidth, .01));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).width, AppTheme.sidebarExpandedWidth);
    await mouse.moveTo(const Offset(600, 300));
    await tester.pump(AppTheme.sidebarExitDelay);
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).width, AppTheme.sidebarCompactWidth);
    expect(tester.getCenter(find.byKey(_homeIcon)), initialIcon);
    expect(tester.getRect(find.byKey(_page)), initialPage);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sematkan sidebar, keyboard dan Escape tetap berfungsi', (
    tester,
  ) async {
    await _shell(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 300));
    await mouse.moveTo(const Offset(32, 32));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-pin')));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_page)).left, 233);
    await mouse.moveTo(const Offset(600, 300));
    await tester.pump(AppTheme.sidebarExitDelay);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(_surface)).width,
      AppTheme.sidebarExpandedWidth,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(_surface)).width,
      AppTheme.sidebarCompactWidth,
    );
    expect(tester.getRect(find.byKey(_page)).left, 65);

    // Switching to the phone layout disposes the rail; the pin is restored
    // together with its reserved space when the window becomes wide again.
    await tester.tapAt(const Offset(32, 32));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 640);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    tester.view.physicalSize = const Size(1000, 640);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(_surface)).width,
      AppTheme.sidebarExpandedWidth,
    );
    expect(tester.getRect(find.byKey(_page)).left, 233);
    await tester.tapAt(const Offset(32, 32));
    await tester.pump(AppTheme.sidebarExitDelay);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_page)).left, 65);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(_surface)).width,
      AppTheme.sidebarExpandedWidth,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(_surface)).width,
      AppTheme.sidebarCompactWidth,
    );
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion tanpa tween dan font besar aman pada jendela pendek',
    (tester) async {
      await _shell(
        tester,
        reducedMotion: true,
        fontScale: 2,
        size: const Size(800, 320),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 200));
      await mouse.moveTo(tester.getCenter(find.byKey(_homeIcon)));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(_surface)).width,
        AppTheme.sidebarExpandedWidth,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('sidebar-destination-/')))
            .height,
        greaterThanOrEqualTo(48),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sidebar-destination-/settings')),
        100,
        scrollable: find.byType(Scrollable),
      );
      expect(tester.takeException(), isNull);
      await mouse.moveTo(const Offset(600, 200));
      await tester.pump(AppTheme.sidebarExitDelay);
      expect(
        tester.getSize(find.byKey(_surface)).width,
        AppTheme.sidebarCompactWidth,
      );
      await mouse.removePointer();
    },
  );

  testWidgets(
    'menu ikon dan tombol tambah mempertahankan callback dan target 48px',
    (tester) async {
      var selected = -1;
      var additions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: LedgySidebar(
                destinations: const [
                  SidebarDestination('/', 'Beranda', Icons.home_outlined),
                  SidebarDestination(
                    '/transactions',
                    'Transaksi',
                    Icons.receipt_long_outlined,
                  ),
                ],
                selectedIndex: 0,
                onSelected: (index) => selected = index,
                onAddTransaction: () => additions++,
              ),
            ),
          ),
        ),
      );
      final add = find.byKey(const ValueKey('sidebar-add-transaction'));
      expect(tester.getSize(add), const Size(48, 48));
      await tester.tap(
        find.byKey(const ValueKey('sidebar-icon-/transactions')),
      );
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(additions, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
