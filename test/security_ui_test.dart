import 'dart:io';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/app/ledgy_app.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/empty_state.dart';
import 'package:ledgy/features/security/presentation/lock_providers.dart';

import 'support/unlocked_app.dart';

void main() {
  final blurAudit = <String, int>{};
  setUpAll(() => initializeDateFormatting('id_ID'));
  tearDownAll(() async {
    final directory = Directory('build/audits');
    await directory.create(recursive: true);
    await File('${directory.path}/phase7-blur.json')
        .writeAsString(jsonEncode(blurAudit));
  });
  test('no raw ledger logging or analytics SDK in production source', () {
    final logging = RegExp(r'\b(print|debugPrint|log)\s*\(');
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      expect(
        logging.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
    final dependencies = File('pubspec.yaml').readAsStringSync();
    expect(
      dependencies,
      isNot(
        matches(
          r'firebase_analytics|sentry_flutter|amplitude_flutter|mixpanel_flutter',
        ),
      ),
    );
  });
  testWidgets('empty state supports 200 percent text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 500),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: EmptyState(
              title: 'Belum ada transaksi',
              message: 'Mulai mencatat transaksi untuk melihat riwayat keuangan Anda.',
              actionLabel: 'Tambah transaksi',
              onAction: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Tambah transaksi'));
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(44),
    );
  });
  for (final route in [
    '/',
    '/transactions',
    '/budget',
    '/accounts',
    '/analysis',
    '/settings',
    '/login',
  ]) {
    testWidgets('blur budget $route and 200 percent font', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      await tester.runAsync(() async {
        await db.select(db.accounts).get();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appLockProvider.overrideWith((ref) => unlockedTestApp()),
          ],
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: LedgyApp(initialLocation: route),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final count = find.byType(BackdropFilter).evaluate().length;
      blurAudit[route] = count;
      expect(
        count,
        // Dashboard's single QuickInputBar is a main glass panel. /analysis
        // redirects there; list rows still receive no additional blur budget.
        lessThanOrEqualTo(
          {'/', '/analysis', '/settings', '/login'}.contains(route) ? 1 : 0,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(db.close);
    });
  }
}
