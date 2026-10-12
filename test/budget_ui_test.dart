import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/app_backdrop.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/local/presentation/advanced_pages.dart';
import 'package:ledgy/features/local/presentation/budget_progress_card.dart';
import 'package:ledgy/features/local/presentation/local_providers.dart';

final _previewKey = GlobalKey();
final _snapshotState = StateProvider<FinanceSnapshot>(
  (ref) => throw StateError('Snapshot fixture required'),
);

class _Finance extends LocalFinanceRepository {
  _Finance(super.db);
  final saved = Completer<void>();
  final deleted = Completer<void>();
  @override
  Future<void> saveBudget(String category, int amount, DateTime month) async {
    await super.saveBudget(category, amount, month);
    saved.complete();
  }

  @override
  Future<void> archiveBudget(String id) async {
    await super.archiveBudget(id);
    deleted.complete();
  }
}

Future<({AppDatabase db, _Finance repo, ProviderContainer container})> _show(
  WidgetTester tester,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final seed = LocalFinanceRepository(db);
  final initial = await seed.snapshot();
  final category = await seed.ensureCategory('Makan & Minum', 'expense');
  await seed.saveBudget('Makan & Minum', 1000000, DateTime.now());
  await seed.saveRule(
    type: 'expense',
    amount: 39000,
    accountId: initial.accounts.first.id,
    categoryId: category,
    note: 'Makan',
    frequency: 'monthly',
    interval: 1,
    next: DateTime.now(),
  );
  await seed.generateDue(DateTime.now());
  final repo = (await tester.runAsync(() async => _Finance(db)))!;
  final data = await seed.snapshot();
  final container = ProviderContainer(
    overrides: [
      localFinanceProvider.overrideWithValue(repo),
      _snapshotState.overrideWith((ref) => data),
      financeSnapshotProvider.overrideWith(
        (ref) async => ref.watch(_snapshotState),
      ),
    ],
  );
  addTearDown(container.dispose);
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
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: _previewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          builder: (context, child) => AppBackdrop(child: child!),
          home: const BudgetPlansPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  return (db: db, repo: repo, container: container);
}

Future<void> _preview(WidgetTester tester, String name) async {
  if (Platform.environment['LEDGY_VISUAL_QA'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
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

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  for (final size in [const Size(360, 800), const Size(1280, 900)]) {
    testWidgets(
      'kartu anggaran ringkas dapat diubah dan dihapus ${size.width.toInt()}px',
      (tester) async {
        final fixture = await _show(tester, size);
        expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
        expect(find.text('Rp 39.000 / Rp 1.000.000'), findsOneWidget);
        expect(find.text('4% terpakai · Sisa Rp 961.000'), findsOneWidget);
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
        await _preview(tester, 'budget-card-${size.width.toInt()}');
        await tester.tap(find.byType(BudgetProgressCard));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        await tester.tap(find.text('Ubah anggaran'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(find.text('Tanggal'), findsOneWidget);
        expect(find.text('Kategori'), findsOneWidget);
        await _preview(tester, 'budget-edit-fields-${size.width.toInt()}');
        await tester.enterText(
          find.widgetWithText(TextField, 'Batas anggaran (Rp)'),
          '2000000',
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Simpan'));
          await fixture.repo.saved.future.timeout(const Duration(seconds: 10));
        });
        final refreshed = (await tester.runAsync(
          () => fixture.repo.snapshot(),
        ))!;
        fixture.container.read(_snapshotState.notifier).state = refreshed;
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        final updated = (await tester.runAsync(() => fixture.repo.snapshot()))!;
        expect(
          updated.budgets.where((b) => b.deletedAt == null).single.amount,
          2000000,
        );
        expect(
          find.text('Rp 39.000 / Rp 2.000.000'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join(' | '),
        );
        await tester.tap(find.byType(BudgetProgressCard));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        await tester.tap(find.text('Hapus anggaran'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        await tester.tap(find.text('Tidak'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(fixture.repo.deleted.isCompleted, isFalse);
        await tester.tap(find.byType(BudgetProgressCard));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        await tester.tap(find.text('Hapus anggaran'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        await tester.tap(find.text('Ya'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        await tester.runAsync(() async {
          await fixture.repo.deleted.future.timeout(
            const Duration(seconds: 10),
          );
        });
        final remaining = (await tester.runAsync(
          () => fixture.repo.snapshot(),
        ))!;
        fixture.container.read(_snapshotState.notifier).state = remaining;
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(find.byType(BudgetProgressCard), findsNothing);
        expect(remaining.transactions.length, updated.transactions.length);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('kolom kategori membuat anggaran pada bulan yang dipilih', (
    tester,
  ) async {
    final fixture = await _show(tester, const Size(360, 800));
    final previous = DateTime(DateTime.now().year, DateTime.now().month - 1);
    await tester.tap(find.byTooltip('Bulan sebelumnya'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    await tester.tap(find.byKey(const ValueKey('budget-actions-menu')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    await tester.tap(find.text('Tambah anggaran'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    final date = find.byKey(const ValueKey('budget-date-field'));
    expect(
      tester.widget<TextFormField>(date).initialValue,
      DateFormat('MMMM yyyy', 'id_ID').format(previous),
    );
    await tester.tap(find.byKey(const ValueKey('budget-category-field')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Cari kategori atau subkategori'),
      'Pesanan Makanan',
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    await tester.tap(find.text('Pesanan Makanan').last);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('budget-category-field')),
          )
          .controller!
          .text,
      'Makan & Minum',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Batas anggaran (Rp)'),
      '250000',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Simpan'));
      await fixture.repo.saved.future.timeout(const Duration(seconds: 10));
    });
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    final snapshot = (await tester.runAsync(() => fixture.repo.snapshot()))!;
    final budget = snapshot.budgets.singleWhere((b) => b.amount == 250000);
    expect(budget.monthStart.toLocal().year, previous.year);
    expect(budget.monthStart.toLocal().month, previous.month);
    expect(snapshot.categoryNames[budget.categoryId], 'Makan & Minum');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
