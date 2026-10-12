import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/app_backdrop.dart';
import 'package:ledgy/features/auth/domain/auth_repository.dart';
import 'package:ledgy/features/dashboard/data/savings_goal_repository.dart';
import 'package:ledgy/features/dashboard/domain/dashboard_summary.dart';
import 'package:ledgy/features/dashboard/presentation/dashboard_page.dart';
import 'package:ledgy/features/dashboard/presentation/dashboard_widgets.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/local/presentation/local_providers.dart';
import 'package:ledgy/features/sync/presentation/sync_providers.dart';
import 'package:ledgy/router/app_router.dart';

FinanceSnapshot fixture(DateTime month) {
  final now = DateTime(month.year, month.month, 3, 12);
  Account asset(String id, int initial, {bool deleted = false}) => Account(
    id: id,
    name: id == 'bank' ? 'Bank Utama' : 'Tunai',
    initialBalance: initial,
    createdAt: DateTime(month.year, month.month - 2),
    updatedAt: now,
    isDirty: false,
    deletedAt: deleted ? now : null,
  );
  Transaction tx(
    String id,
    String type,
    int amount,
    DateTime date, {
    String? note,
    String? category,
    String? target,
    bool deleted = false,
  }) => Transaction(
    id: id,
    type: type,
    amount: amount,
    accountId: 'bank',
    categoryId: category,
    toAccountId: target,
    note: note,
    occurredAt: date,
    createdAt: now,
    updatedAt: now,
    isDirty: false,
    deletedAt: deleted ? now : null,
  );
  return FinanceSnapshot(
    [
      asset('bank', 100000000),
      asset('cash', 26550000),
      asset('archived', 99999999, deleted: true),
    ],
    [
      for (final entry in [
        ('food', 'Makan & Minum'),
        ('transport', 'Transportasi'),
        ('shopping', 'Belanja'),
        ('utilities', 'Tagihan'),
        ('cafe', 'Makan & Minum • Cafe / Warkop'),
      ])
        Category(
          id: entry.$1,
          name: entry.$2,
          kind: 'expense',
          createdAt: now,
          updatedAt: now,
          isDirty: false,
        ),
    ],
    [
      tx('salary', 'income', 24500000, now, note: 'Gaji Bulanan'),
      tx('coffee', 'expense', 35000, now, note: 'Kopi Susu', category: 'cafe'),
      tx(
        'food',
        'expense',
        3165000,
        DateTime(month.year, month.month, 4),
        category: 'food',
        note: 'Belanja makanan',
      ),
      tx(
        'transport',
        'expense',
        800000,
        DateTime(month.year, month.month, 10),
        category: 'transport',
      ),
      tx(
        'shopping',
        'expense',
        1900000,
        DateTime(month.year, month.month, 17),
        category: 'shopping',
      ),
      tx(
        'utilities',
        'expense',
        1200000,
        DateTime(month.year, month.month, 24),
        category: 'utilities',
      ),
      tx(
        'other',
        'expense',
        9100000,
        DateTime(month.year, month.month, 29),
        note: 'Kebutuhan lain',
      ),
      tx('transfer', 'transfer', 1000000, now, target: 'cash'),
      tx('deleted', 'expense', 999999, now, deleted: true),
      tx(
        'previous',
        'expense',
        100000,
        DateTime(month.year, month.month - 1, 5),
        note: 'Buku bulan lalu',
      ),
    ],
    [
      for (final entry in [
        ('food', 4000000),
        ('transport', 1500000),
        ('shopping', 2000000),
        ('utilities', 1500000),
      ])
        Budget(
          id: entry.$1,
          categoryId: entry.$1,
          amount: entry.$2,
          monthStart: month,
          createdAt: now,
          updatedAt: now,
          isDirty: false,
        ),
    ],
    [],
  );
}

class MemoryGoals extends SavingsGoalRepository {
  MemoryGoals(super.finance);
  List<SavingsGoal> goals = [
    const SavingsGoal(
      id: 'emergency',
      name: 'Dana Darurat',
      target: 25000000,
      saved: 15000000,
    ),
    const SavingsGoal(
      id: 'holiday',
      name: 'Liburan Akhir Tahun',
      target: 12000000,
      saved: 8000000,
    ),
  ];
  @override
  Future<List<SavingsGoal>> read() async => goals;
  @override
  Future<void> write(List<SavingsGoal> next) async {
    goals = next;
  }
}

final previewKey = GlobalKey();
Future<void> preview(WidgetTester tester, String name) async {
  if (Platform.environment['LEDGY_VISUAL_QA'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(previewKey),
  );
  void repaint(RenderObject node) {
    node.markNeedsPaint();
    node.visitChildren(repaint);
  }

  repaint(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 1);
    final bytes = await picture.toByteData(format: ImageByteFormat.png);
    await Directory('build/ui-previews').create(recursive: true);
    await File('build/ui-previews/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

Future<MemoryGoals> showDashboard(
  WidgetTester tester,
  Size size, {
  double fontScale = 1,
  FinanceSnapshot? snapshot,
  List<SavingsGoal>? initialGoals,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = LocalFinanceRepository(db);
  final goals = MemoryGoals(repo);
  if (initialGoals != null) goals.goals = initialGoals;
  final now = DateTime.now();
  final data = snapshot ?? fixture(DateTime(now.year, now.month));
  final router = createAppRouter();
  addTearDown(router.dispose);
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
        databaseProvider.overrideWithValue(db),
        localFinanceProvider.overrideWithValue(repo),
        savingsGoalRepositoryProvider.overrideWithValue(goals),
        financeSnapshotProvider.overrideWith((ref) async => data),
        accountsProvider.overrideWith(
          (ref) => Stream.value(
            data.accounts.where((a) => a.deletedAt == null).toList(),
          ),
        ),
        categoriesProvider.overrideWith((ref) => Stream.value(data.categories)),
        transactionsProvider.overrideWith(
          (ref) => Stream.value(
            data.transactions.where((t) => t.deletedAt == null).toList(),
          ),
        ),
        cloudUserProvider.overrideWith(
          (ref) => Stream.value(
            const CloudUser('a', 'a@example.com', name: 'Abiyyu'),
          ),
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(fontScale)),
          child: RepaintBoundary(
            key: previewKey,
            child: AppBackdrop(child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return goals;
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  test('dashboard excludes archived entries, includes subcategories, conserves transfers', () {
    final month = DateTime(2026, 10);
    final summary = DashboardSummary(fixture(month), month);
    expect(summary.netWorth, 134750000);
    expect(summary.cashflow.income, 24500000);
    expect(summary.cashflow.expense, 16200000);
    expect(summary.savingsRatio, closeTo(8300000 / 24500000, .00001));
    expect(summary.budgets.first.spent, 3200000);
    expect(
      summary.weekly.map((p) => p.expense).reduce((a, b) => a + b),
      16200000,
    );
    expect(summary.recent('').any((t) => t.id == 'previous'), isFalse);
    expect(summary.recent('buku').single.id, 'previous');
    expect(summary.recent('Makan & Minum').length, 2);
    expect(summary.recent('999999'), isEmpty);
  });

  test(
    'calendar buckets cover leap February and zero-income ratio stays finite',
    () {
      final summary = DashboardSummary(
        const FinanceSnapshot([], [], [], [], []),
        DateTime(2024, 2),
      );
      expect(summary.weekly.length, 5);
      expect(summary.savingsRatio, isNull);
      expect(summary.netWorth, 0);
      expect(summary.cashflow.net, 0);
    },
  );

  test('savings targets persist across repository recreation and reject invalid data', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SavingsGoalRepository(LocalFinanceRepository(db));
    expect(await repo.read(), isEmpty);
    await repo.write([
      const SavingsGoal(
        id: 'a',
        name: 'Dana darurat',
        target: 2000000,
        saved: 3000000,
      ),
    ]);
    final loaded = await SavingsGoalRepository(LocalFinanceRepository(db))
        .read();
    expect(loaded.single.saved, 3000000);
    expect(loaded.single.progress, 1.5);
    await expectLater(
      repo.write([
        const SavingsGoal(id: 'a', name: 'Dana', target: 0, saved: 0),
      ]),
      throwsArgumentError,
    );
    expect((await repo.read()).single.target, 2000000);
    await repo.write([]);
    expect(await repo.read(), isEmpty);
  });

  for (final size in [const Size(1440, 1050), const Size(390, 844)]) {
    testWidgets(
      'dashboard responsive, functional search and period ${size.width}',
      (tester) async {
        await showDashboard(tester, size);
        expect(find.byType(DashboardPage), findsOneWidget);
        expect(find.text('Analisis'), findsNothing);
        expect(find.byType(DashboardMetric), findsNWidgets(4));
        expect(find.text('33,9%'), findsOneWidget);
        expect(
          tester
              .widget<LineChart>(find.byType(LineChart))
              .data
              .lineBarsData
              .length,
          2,
        );
        await preview(tester, 'dashboard-${size.width.toInt()}');
        await tester.enterText(
          find.byKey(const ValueKey('dashboard-search')),
          'buku',
        );
        await tester.pumpAndSettle();
        expect(find.text('Buku bulan lalu'), findsOneWidget);
        expect(find.text('Gaji Bulanan'), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('dashboard-search')),
          'Tidak ditemukan',
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Tidak ada transaksi yang cocok'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('dashboard-search')),
          '',
        );
        await tester.tap(
          find.byKey(const ValueKey('dashboard-previous-month')),
        );
        await tester.pumpAndSettle();
        final previous = DateTime(
          DateTime.now().year,
          DateTime.now().month - 1,
        );
        expect(
          find.text(DateFormat('MMMM yyyy', 'id_ID').format(previous)),
          findsOneWidget,
        );
        expect(find.text('Belum ada pemasukan bulan ini'), findsOneWidget);
        for (final period in CashflowPeriod.values) {
          await tester.ensureVisible(find.byTooltip('Periode grafik arus kas'));
          await tester.tap(find.byTooltip('Periode grafik arus kas'));
          await tester.pumpAndSettle();
          expect(find.text('6 bulan'), findsNothing);
          expect(find.text('Harian'), findsNothing);
          await tester.tap(find.text(period.label).last);
          await tester.pumpAndSettle();
          final chart = tester.widget<DashboardCashflowChart>(
            find.byType(DashboardCashflowChart),
          );
          expect(chart.period, period);
          expect(
            chart.points.length,
            DashboardSummary(
              fixture(DateTime(DateTime.now().year, DateTime.now().month)),
              previous,
            ).trend(period).length,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'income card opens corresponding month and type; new transaction works',
    (tester) async {
      await showDashboard(tester, const Size(1440, 1000));
      await tester.tap(find.byKey(const ValueKey('dashboard-previous-month')));
      await tester.pumpAndSettle();
      final previous = DateTime(DateTime.now().year, DateTime.now().month - 1);
      await tester.tap(
        find.widgetWithText(
          DashboardMetric,
          'Pemasukan (${DateFormat('MMM', 'id_ID').format(previous)})',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsNothing);
      expect(
        find.text(DateFormat('MMMM yyyy', 'id_ID').format(previous)),
        findsOneWidget,
      );
      expect(find.text('Buku bulan lalu'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar-icon-/')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dashboard-previous-month')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Lihat semua anggaran'));
      await tester.tap(find.byTooltip('Lihat semua anggaran'));
      await tester.pumpAndSettle();
      expect(
        find.text(DateFormat('MMMM yyyy', 'id_ID').format(previous)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-icon-/')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transaksi Baru'));
      await tester.pumpAndSettle();
      expect(find.text('Simpan transaksi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('targets can be created, edited, and removed', (tester) async {
    final goals = await showDashboard(tester, const Size(1440, 1050));
    final panel = find.widgetWithText(DashboardPanel, 'Target Tabungan');
    final originalSize = tester.getSize(panel);
    await tester.ensureVisible(
      find.byKey(const ValueKey('dashboard-add-goal')),
    );
    await tester.tap(find.byKey(const ValueKey('dashboard-add-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Isi nama target.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama target'),
      'Rumah',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Target (Rp)'),
      '100000000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Jumlah terkumpul (Rp)'),
      '20000000',
    );
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(goals.goals.last.name, 'Rumah');
    expect(tester.getSize(panel), originalSize);
    await tester.ensureVisible(find.text('Rumah'));
    await tester.tap(find.text('Rumah'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Jumlah terkumpul (Rp)'),
      '30000000',
    );
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(goals.goals.last.saved, 30000000);
    await tester.tap(find.text('Rumah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus').last);
    await tester.pumpAndSettle();
    expect(goals.goals.any((g) => g.name == 'Rumah'), isFalse);
    expect(tester.getSize(panel), originalSize);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(1440, 1050), const Size(390, 844)]) {
    testWidgets(
      'panels stay equal and added content scrolls independently ${size.width}',
      (tester) async {
        final month = DateTime(DateTime.now().year, DateTime.now().month);
        final base = fixture(month);
        final data = FinanceSnapshot(
          base.accounts,
          [
            ...base.categories,
            for (var i = 0; i < 16; i++)
              base.categories.first.copyWith(
                id: 'extra-$i',
                name: 'Kategori tambahan $i',
              ),
          ],
          [
            ...base.transactions,
            for (var i = 0; i < 16; i++)
              base.transactions.first.copyWith(
                id: 'extra-$i',
                note: Value('Transaksi tambahan $i'),
              ),
          ],
          [
            ...base.budgets,
            for (var i = 0; i < 16; i++)
              base.budgets.first.copyWith(
                id: 'extra-$i',
                categoryId: 'extra-$i',
              ),
          ],
          base.rules,
        );
        await showDashboard(
          tester,
          size,
          snapshot: data,
          initialGoals: [
            for (var i = 0; i < 16; i++)
              SavingsGoal(
                id: '$i',
                name: 'Target tambahan $i',
                target: 10000000,
                saved: i * 100000,
              ),
          ],
        );
        final panels = find.byType(DashboardPanel);
        expect(panels, findsNWidgets(5));
        final panelSize = tester.getSize(panels.first);
        for (final element in panels.evaluate()) {
          expect(tester.getSize(find.byWidget(element.widget)), panelSize);
        }
        final metricSize = tester.getSize(find.byType(DashboardMetric).first);
        for (final element in find.byType(DashboardMetric).evaluate()) {
          expect(tester.getSize(find.byWidget(element.widget)), metricSize);
        }
        final budget = find.widgetWithText(
          DashboardPanel,
          'Alokasi & Kinerja Anggaran',
        );
        final recent = find.widgetWithText(
          DashboardPanel,
          'Transaksi Terakhir',
        );
        final goals = find.widgetWithText(DashboardPanel, 'Target Tabungan');
        final outer = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('dashboard-scroll')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        for (final panel in [budget, recent, goals]) {
          final scrollbar = tester.widget<Scrollbar>(
            find.descendant(of: panel, matching: find.byType(Scrollbar)),
          );
          expect(scrollbar.thumbVisibility, isTrue);
          expect(
            scrollbar.controller!.position.maxScrollExtent,
            greaterThan(0),
          );
          await tester.ensureVisible(panel);
          await tester.pumpAndSettle();
          final pageOffset = outer.pixels;
          await tester.drag(
            find.descendant(
              of: panel,
              matching: find.byType(SingleChildScrollView),
            ),
            const Offset(0, -3000),
          );
          await tester.pumpAndSettle();
          expect(scrollbar.controller!.offset, greaterThan(0));
          expect(outer.pixels, pageOffset);
          expect(tester.getSize(panel), panelSize);
        }
        // All entries remain available inside their own fixed viewport.
        expect(find.text('Kategori tambahan 15'), findsOneWidget);
        expect(find.text('Transaksi tambahan 15'), findsOneWidget);
        expect(find.text('Target tambahan 15').hitTestable(), findsOneWidget);
        await preview(tester, 'dashboard-scroll-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('dashboard supports 200 percent text on a narrow screen', (
    tester,
  ) async {
    await showDashboard(tester, const Size(390, 844), fontScale: 2);
    await preview(tester, 'dashboard-large-font');
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('dashboard-scroll')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
