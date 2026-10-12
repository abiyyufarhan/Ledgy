import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/dashboard/presentation/dashboard_page.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/local/data/local_notifications.dart';
import 'package:ledgy/features/local/presentation/local_automation_host.dart';
import 'package:ledgy/features/local/presentation/advanced_pages.dart';
import 'package:ledgy/features/local/presentation/local_providers.dart';
import 'package:ledgy/features/auth/presentation/profile_menu.dart';

class _Notifications extends LocalNotifications {
  _Notifications(this.allowed);
  final bool allowed;
  int requests = 0;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return allowed;
  }
}

class _Finance extends LocalFinanceRepository {
  _Finance(super.db);
  int checks = 0;
  @override
  Future<void> checkBudgets(DateTime now, BudgetNotifier notify) async {
    checks++;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  for (final size in [const Size(400, 800), const Size(1280, 900)]) {
    for (final page in ['budget', 'recurring', 'reports', 'csv']) {
      testWidgets('$page responsif ${size.width.toInt()}px', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = _Finance(db);
        final notifications = _Notifications(
          size.width >= AppTheme.sidebarBreakpoint,
        );
        final initial = await repo.snapshot();
        final category = await repo.ensureCategory('Tagihan', 'expense');
        await repo.saveBudget('Tagihan', 1000000, DateTime.now());
        await repo.saveRule(
          type: 'expense',
          amount: 700000,
          accountId: initial.accounts.first.id,
          categoryId: category,
          note: 'Listrik bulanan',
          frequency: 'monthly',
          interval: 1,
          next: DateTime.now(),
        );
        await repo.generateDue(DateTime.now());
        final data = await repo.snapshot();
        final widget = switch (page) {
          'budget' => const BudgetPlansPage(),
          'recurring' => const RecurringPage(),
          'reports' => const DashboardPage(),
          _ => const CsvPage(),
        };
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localFinanceProvider.overrideWithValue(repo),
              localNotificationsProvider.overrideWithValue(notifications),
              financeSnapshotProvider.overrideWith((ref) async => data),
            ],
            child: MaterialApp(theme: AppTheme.dark, home: widget),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byType(ProfileMenu),
          size.width < AppTheme.sidebarBreakpoint
              ? findsOneWidget
              : findsNothing,
        );
        if (page == 'budget') {
          expect(find.text('Tagihan'), findsOneWidget);
          expect(find.text('Aktifkan notifikasi'), findsNothing);
          await tester.tap(find.byKey(const ValueKey('budget-actions-menu')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Aktifkan notifikasi'));
          await tester.pumpAndSettle();
          expect(notifications.requests, 1);
          expect(repo.checks, 1);
          expect(
            find.textContaining(
              notifications.allowed
                  ? 'Notifikasi diaktifkan.'
                  : 'Izin notifikasi belum diberikan.',
            ),
            findsOneWidget,
          );
        }
        if (page == 'recurring') {
          expect(find.text('Listrik bulanan'), findsOneWidget);
        }
        if (page == 'reports') {
          expect(find.text('Tren Arus Kas'), findsOneWidget);
        }
        if (page == 'csv') expect(find.text('Pilih CSV'), findsOneWidget);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
