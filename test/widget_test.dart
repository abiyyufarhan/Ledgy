import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/app/ledgy_app.dart';
import 'package:ledgy/app/mvp_screens.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/security/presentation/lock_providers.dart';

import 'support/unlocked_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('menampilkan halaman awal Ledgy', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLockProvider.overrideWith((ref) => unlockedTestApp())],
        child: LedgyApp(initialLocation: '/onboarding'),
      ),
    );

    expect(find.text('Ledgy'), findsOneWidget);
  });

  testWidgets('onboarding berlanjut saat Mulai ditekan', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLockProvider.overrideWith((ref) => unlockedTestApp())],
        child: LedgyApp(initialLocation: '/onboarding'),
      ),
    );

    await tester.tap(find.text('Mulai'));
    await tester.pumpAndSettle();

    expect(find.text('Catat dengan tenang'), findsOneWidget);
  });

  testWidgets(
    'editor transaksi desktop menampilkan kontrol pada dialog gelap',
    (tester) async {
      final now = DateTime.utc(2026, 1, 1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountsProvider.overrideWith(
              (ref) => Stream.value([
                Account(
                  id: 'cash',
                  createdAt: now,
                  updatedAt: now,
                  isDirty: false,
                  name: 'Tunai',
                  initialBalance: 0,
                ),
              ]),
            ),
            categoriesProvider.overrideWith(
              (ref) => Stream.value([
                Category(
                  id: 'food',
                  createdAt: now,
                  updatedAt: now,
                  isDirty: false,
                  name: 'Makan & Minum',
                  kind: 'expense',
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showTransactionEditor(context),
                  child: const Text('Buka editor'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka editor'));
      await tester.pumpAndSettle();

      expect(find.text('Keluar'), findsOneWidget);
      expect(find.text('Jumlah'), findsOneWidget);
      expect(find.text('000'), findsNothing);
      expect(find.text('Simpan transaksi'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '3000000');
      await tester.pump();

      expect(find.text('3.000.000'), findsOneWidget);
    },
  );
}
