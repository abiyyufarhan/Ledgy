import 'dart:io';
import 'dart:ui' show ImageByteFormat;

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
import 'package:ledgy/core/widgets/glass_dropdown_field.dart';
import 'package:ledgy/core/widgets/app_backdrop.dart';
import 'package:ledgy/features/reports/data/finance_report_exporter.dart';
import 'package:ledgy/features/transactions/domain/transaction_period.dart';
import 'package:ledgy/features/transactions/presentation/transaction_history_page.dart';
import 'package:ledgy/features/transactions/presentation/transaction_toolbar_icon.dart';

final now = DateTime.now();
final _previewKey = GlobalKey();
bool _fontsLoaded = false;
Future<void> preview(WidgetTester tester, String name) async {
  if (Platform.environment['LEDGY_VISUAL_QA'] != '1') return;
  final boundary =
      _previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final folder = Directory('build/ui-previews');
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

final month = DateTime(now.year, now.month);
final accounts = [
  for (final id in ['cash', 'bank'])
    Account(
      id: id,
      createdAt: month,
      updatedAt: month,
      isDirty: false,
      name: id == 'cash' ? 'Tunai' : 'Bank Jago',
      initialBalance: 0,
    ),
];
final categories = [
  Category(
    id: 'cafe',
    createdAt: month,
    updatedAt: month,
    isDirty: false,
    name: 'Makanan & Minuman • Cafe /Warkop',
    kind: 'expense',
  ),
  Category(
    id: 'salary',
    createdAt: month,
    updatedAt: month,
    isDirty: false,
    name: 'Gaji',
    kind: 'income',
  ),
  Category(
    id: 'custom',
    createdAt: month,
    updatedAt: month,
    isDirty: false,
    name: 'Kategori Pribadi • Khusus',
    kind: 'expense',
  ),
];
Transaction row(
  String id,
  String type,
  int amount,
  String note, {
  String? category,
  String account = 'cash',
  DateTime? date,
}) => Transaction(
  id: id,
  createdAt: month,
  updatedAt: month,
  isDirty: false,
  type: type,
  amount: amount,
  note: note,
  categoryId: category,
  accountId: account,
  toAccountId: type == 'transfer' ? 'bank' : null,
  occurredAt: (date ?? month).toUtc(),
);
final transactions = [
  row(
    'salary',
    'income',
    1000,
    'Gaji bulan ini',
    category: 'salary',
    account: 'bank',
  ),
  row('coffee', 'expense', 200, 'Kopi bulan ini', category: 'cafe'),
  row('transfer', 'transfer', 500, 'Transfer bulan ini'),
  row(
    'old',
    'expense',
    50,
    'Arsip bulan lalu',
    category: 'cafe',
    date: DateTime(month.year, month.month - 1),
  ),
];

Future<void> showPage(
  WidgetTester tester, {
  Size size = const Size(1200, 1000),
  double scale = 1,
  Future<bool> Function(TransactionReport, FinanceReportFormat)? export,
  List<Transaction>? rows,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (Platform.environment['LEDGY_VISUAL_QA'] == '1' && !_fontsLoaded) {
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader(
        'Manrope',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    });
    _fontsLoaded = true;
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountsProvider.overrideWith((ref) => Stream.value(accounts)),
        categoriesProvider.overrideWith((ref) => Stream.value(categories)),
        transactionsProvider.overrideWith(
          (ref) => Stream.value(rows ?? transactions),
        ),
        transactionReportExportProvider.overrideWithValue(
          export ?? (_, _) async => false,
        ),
      ],
      child: RepaintBoundary(
        key: _previewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: AppBackdrop(child: child!),
          ),
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: TransactionHistoryPage(
              initialType: null,
              transactionBuilder: (t) => ListTile(title: Text(t.note!)),
              onAdd: () {},
              categoryIcon: (_) => Icons.restaurant,
              categoryColor: (_) => AppTheme.transactionIncome,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('transaction-filter-button')));
  await tester.pumpAndSettle();
}

Future<void> chooseType(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('transaction-filter-type')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> apply(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Terapkan'));
  await tester.tap(find.text('Terapkan'));
  await tester.pumpAndSettle();
}

Future<void> choosePeriod(WidgetTester tester, TransactionPeriod period) async {
  await tester.tap(find.byKey(const ValueKey('transaction-calendar-button')));
  await tester.pumpAndSettle();
  expect(find.text('Pilih periode'), findsOneWidget);
  expect(find.byType(OutlinedButton), findsNWidgets(3));
  await preview(tester, 'transaction-period-options');
  await tester.tap(find.byKey(ValueKey('transaction-period-${period.name}')));
  await tester.pumpAndSettle();
}

Future<void> download(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('transaction-export-button')));
  await tester.pumpAndSettle();
  expect(find.text('PDF'), findsOneWidget);
  expect(find.text('Excel'), findsOneWidget);
  await preview(tester, 'transaction-export-dropdown');
  if (tester.view.physicalSize.width < 700) {
    await preview(tester, 'transaction-export-dropdown-small');
  }
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  testWidgets('filter/unduh tetap tampak ketika daftar transaksi kosong', (
    tester,
  ) async {
    await showPage(tester, rows: []);
    final filter = find.byKey(const ValueKey('transaction-filter-button'));
    final download = find.byKey(const ValueKey('transaction-export-button'));
    final calendar = find.byKey(const ValueKey('transaction-calendar-button'));
    expect(filter, findsOneWidget);
    expect(download, findsOneWidget);
    expect(calendar, findsOneWidget);
    expect(find.byType(TransactionToolbarIcon), findsNWidgets(2));
    expect(tester.widget<IconButton>(filter).onPressed, isNotNull);
    final downloadButton = tester.widget<IconButton>(download);
    expect(downloadButton.onPressed, isNull);
    expect(
      downloadButton.style!.foregroundColor!.resolve({WidgetState.disabled}),
      AppTheme.mutedText,
    );
    for (final button in [filter, calendar, download]) {
      expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(button).right, lessThanOrEqualTo(1200));
    }
    await openFilter(tester);
    expect(find.text('Filter Transaksi'), findsOneWidget);
    await preview(tester, 'transaction-filter-text-only');
    expect(tester.takeException(), isNull);
  });
  testWidgets('toolbar baru, jumlah bulanan dan panah bulan', (tester) async {
    await showPage(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(GlassDropdownFormField<String?>), findsNothing);
    expect(
      find.text(DateFormat('MMMM yyyy', 'id_ID').format(month)),
      findsOneWidget,
    );
    expect(find.text('Rp 1.000'), findsOneWidget);
    expect(find.text('Rp 200'), findsOneWidget);
    expect(find.text('Arsip bulan lalu'), findsNothing);
    await tester.tap(find.byTooltip('Bulan sebelumnya'));
    await tester.pumpAndSettle();
    expect(find.text('Arsip bulan lalu'), findsOneWidget);
    expect(find.text('Gaji bulan ini'), findsNothing);
    expect(find.text('Rp 50'), findsOneWidget);
    await tester.tap(find.byTooltip('Bulan berikutnya'));
    await tester.pumpAndSettle();
    expect(find.text('Gaji bulan ini'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('filter diterapkan hanya saat Terapkan, reset menghapus filter', (
    tester,
  ) async {
    await showPage(tester);
    await openFilter(tester);
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, 'Reset')).width,
      tester.getSize(find.widgetWithText(FilledButton, 'Terapkan')).width,
    );
    await chooseType(tester, 'Pemasukan');
    await tester.tap(find.byTooltip('Tutup filter'));
    await tester.pumpAndSettle();
    expect(find.text('Kopi bulan ini'), findsOneWidget);
    await openFilter(tester);
    await chooseType(tester, 'Pemasukan');
    await apply(tester);
    expect(find.text('Gaji bulan ini'), findsOneWidget);
    expect(find.text('Kopi bulan ini'), findsNothing);
    expect(find.text('Transfer bulan ini'), findsNothing);
    await openFilter(tester);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await apply(tester);
    expect(find.text('Kopi bulan ini'), findsOneWidget);
    expect(find.text('Transfer bulan ini'), findsOneWidget);
  });
  testWidgets('kategori bertingkat dan akun milik pengguna', (tester) async {
    await showPage(tester);
    await openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('transaction-filter-category')));
    await tester.pumpAndSettle();
    expect(find.text('Amal & Donasi'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Makan & Minum'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Makan & Minum'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cafe / Warkop'));
    await tester.tap(find.text('Cafe / Warkop'));
    await tester.pumpAndSettle();
    expect(find.text('Makan & Minum • Cafe / Warkop'), findsOneWidget);
    await apply(tester);
    expect(find.text('Kopi bulan ini'), findsOneWidget);
    expect(find.text('Gaji bulan ini'), findsNothing);
    await openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('transaction-filter-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank Jago').last);
    await tester.pumpAndSettle();
    await apply(tester);
    expect(find.text('Tidak ada transaksi yang cocok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dropdown PDF/XLSX mengekspor hanya transaksi yang terlihat', (
    tester,
  ) async {
    Set<String>? exported;
    DateTime? selected;
    final formats = <FinanceReportFormat>[];
    await showPage(
      tester,
      export: (report, format) async {
        exported = report.transactions.map((t) => t.id).toSet();
        selected = report.date;
        formats.add(format);
        return true;
      },
    );
    await openFilter(tester);
    await chooseType(tester, 'Pemasukan');
    await apply(tester);
    await download(tester, 'PDF');
    expect(exported, {'salary'});
    expect(selected, DateTime(now.year, now.month, now.day));
    expect(find.text('Laporan PDF berhasil disimpan.'), findsOneWidget);
    await download(tester, 'Excel');
    expect(exported, {'salary'});
    expect(formats, [FinanceReportFormat.pdf, FinanceReportFormat.xlsx]);
  });
  testWidgets('gagal ekspor menampilkan pesan aman dan dapat dicoba ulang', (
    tester,
  ) async {
    var calls = 0;
    await showPage(
      tester,
      export: (_, _) async {
        if (++calls == 1) throw StateError('private ledger content');
        return true;
      },
    );
    await download(tester, 'PDF');
    expect(
      find.text('Laporan belum dapat disimpan. Coba lagi.'),
      findsOneWidget,
    );
    expect(find.textContaining('private ledger content'), findsNothing);
    await download(tester, 'Excel');
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter dan ringkasan responsif pada font 200% di layar kecil', (
    tester,
  ) async {
    await showPage(tester, size: const Size(360, 550), scale: 2);
    expect(tester.takeException(), isNull);
    await openFilter(tester);
    await tester.ensureVisible(find.text('Terapkan'));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('transaction-filter-button')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
    await apply(tester);
    expect(tester.takeException(), isNull);
    await download(tester, 'PDF');
    expect(tester.takeException(), isNull);
    await choosePeriod(tester, TransactionPeriod.daily);
    expect(tester.takeException(), isNull);
  });

  testWidgets('harian/bulanan/tahunan mengubah daftar, jumlah dan navigasi', (
    tester,
  ) async {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final anotherMonth = DateTime(now.year, now.month == 1 ? 2 : 1, 10);
    TransactionReport? exported;
    await showPage(
      tester,
      rows: [
        row('today', 'expense', 100, 'Hari ini', date: today),
        row('yesterday', 'income', 300, 'Kemarin', date: yesterday),
        row('other-month', 'expense', 200, 'Bulan lain', date: anotherMonth),
        row(
          'last-year',
          'expense',
          400,
          'Tahun lalu',
          date: DateTime(now.year - 1, 10),
        ),
        row('transfer', 'transfer', 500, 'Transfer hari ini', date: today),
      ],
      export: (report, _) async {
        exported = report;
        return true;
      },
    );
    await choosePeriod(tester, TransactionPeriod.daily);
    expect(find.text(TransactionPeriod.daily.title(today)), findsOneWidget);
    expect(find.text('Hari ini'), findsOneWidget);
    expect(find.text('Kemarin'), findsNothing);
    expect(find.text('Bulan lain'), findsNothing);
    expect(find.text('Rp 100'), findsOneWidget);
    expect(find.text('Rp 0'), findsOneWidget);
    await download(tester, 'PDF');
    expect(exported!.period, TransactionPeriod.daily);
    expect(exported!.transactions.map((t) => t.id).toSet(), {
      'today',
      'transfer',
    });
    await tester.tap(find.byTooltip('Hari sebelumnya'));
    await tester.pumpAndSettle();
    expect(find.text('Kemarin'), findsOneWidget);
    expect(find.text('Hari ini'), findsNothing);
    await tester.tap(find.byTooltip('Hari berikutnya'));
    await tester.pumpAndSettle();
    await choosePeriod(tester, TransactionPeriod.yearly);
    expect(find.text('${now.year}'), findsOneWidget);
    expect(find.text('Bulan lain'), findsOneWidget);
    expect(find.text('Tahun lalu'), findsNothing);
    expect(
      find.text('Rp 300'),
      findsNWidgets(yesterday.year == now.year ? 2 : 1),
    );
    await download(tester, 'Excel');
    expect(exported!.period, TransactionPeriod.yearly);
    expect(exported!.expense, 300);
    expect(exported!.transactions.any((t) => t.id == 'last-year'), isFalse);
    await tester.tap(find.byTooltip('Tahun sebelumnya'));
    await tester.pumpAndSettle();
    expect(find.text('Tahun lalu'), findsOneWidget);
    expect(find.text('Rp 400'), findsOneWidget);
    await tester.tap(find.byTooltip('Tahun berikutnya'));
    await tester.pumpAndSettle();
    await choosePeriod(tester, TransactionPeriod.monthly);
    expect(find.text(TransactionPeriod.monthly.title(today)), findsOneWidget);
    expect(find.text('Bulan lain'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menutup dropdown atau membatalkan penyimpanan tidak mengunduh', (
    tester,
  ) async {
    var calls = 0;
    await showPage(
      tester,
      export: (_, _) async {
        calls++;
        return false;
      },
    );
    await tester.tap(find.byKey(const ValueKey('transaction-export-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await download(tester, 'PDF');
    expect(calls, 1);
    expect(find.text('Laporan PDF berhasil disimpan.'), findsNothing);
    expect(find.text('Laporan belum dapat disimpan. Coba lagi.'), findsNothing);
  });
}
