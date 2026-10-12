import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/features/reports/data/finance_report_exporter.dart';
import 'package:ledgy/features/transactions/domain/transaction_period.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));
  final date = DateTime(2026, 10, 7);
  final accounts = [
    Account(
      id: 'cash',
      name: 'Tunai',
      initialBalance: 0,
      createdAt: date,
      updatedAt: date,
      isDirty: false,
    ),
  ];
  final categories = [
    Category(
      id: 'food',
      name: 'Makanan & Minuman • Cafe /Warkop',
      kind: 'expense',
      createdAt: date,
      updatedAt: date,
      isDirty: false,
    ),
  ];
  Transaction row(
    String id,
    String type,
    int amount, {
    DateTime? occurredAt,
    DateTime? deletedAt,
    String? note,
  }) => Transaction(
    id: id,
    type: type,
    amount: amount,
    accountId: 'cash',
    categoryId: 'food',
    occurredAt: (occurredAt ?? date).toUtc(),
    note: note,
    deletedAt: deletedAt,
    createdAt: date,
    updatedAt: date,
    isDirty: false,
  );
  TransactionReport report(
    List<Transaction> rows, {
    TransactionPeriod period = TransactionPeriod.monthly,
  }) => TransactionReport(
    transactions: rows,
    accounts: accounts,
    categories: categories,
    date: date,
    period: period,
  );

  test(
    'XLSX dapat dibaca kembali dengan jumlah numerik dan catatan berupa teks',
    () async {
      final data = report([
        row('income', 'income', 1000),
        row('expense', 'expense', 250, note: '=SUM(A1:A2)'),
        row('transfer', 'transfer', 500),
        row('deleted', 'expense', 100, deletedAt: date),
        row('other-month', 'expense', 200, occurredAt: DateTime(2026, 9)),
      ]);
      final bytes = await FinanceReportExporter.encode(
        data,
        FinanceReportFormat.xlsx,
      );
      if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
        final folder = Directory('build/report-previews');
        await folder.create(recursive: true);
        await File('${folder.path}/laporan-contoh.xlsx').writeAsBytes(bytes);
      }
      final book = xlsx.Excel.decodeBytes(bytes);
      expect(book.tables.keys.toSet(), {'Ringkasan', 'Transaksi'});
      final summary = book['Ringkasan'].rows;
      expect(summary[1][1]!.value, xlsx.IntCellValue(3));
      expect(summary[2][1]!.value, xlsx.IntCellValue(1000));
      expect(summary[3][1]!.value, xlsx.IntCellValue(250));
      expect(summary[4][1]!.value, xlsx.IntCellValue(750));
      final rows = book['Transaksi'].rows;
      expect(rows, hasLength(4));
      expect(rows[2][5]!.value, xlsx.TextCellValue('=SUM(A1:A2)'));
      expect(rows[2][6]!.value, xlsx.IntCellValue(250));
      expect(
        rows[2][4]!.value,
        xlsx.TextCellValue('Makan & Minum • Cafe / Warkop'),
      );
    },
  );

  test(
    'nama berkas dan cakupan laporan mengikuti periode harian dan tahunan',
    () {
      final rows = [
        row('today', 'expense', 100),
        row('yesterday', 'expense', 200, occurredAt: DateTime(2026, 10, 6)),
        row('other-month', 'expense', 300, occurredAt: DateTime(2026, 1)),
        row('last-year', 'expense', 400, occurredAt: DateTime(2025, 10)),
      ];
      final daily = report(rows, period: TransactionPeriod.daily);
      expect(daily.expense, 100);
      expect(
        daily.fileName(FinanceReportFormat.pdf),
        'ledgy-laporan-daily-2026-10-07.pdf',
      );
      final yearly = report(rows, period: TransactionPeriod.yearly);
      expect(yearly.expense, 600);
      expect(
        yearly.fileName(FinanceReportFormat.xlsx),
        'ledgy-laporan-yearly-2026.xlsx',
      );
    },
  );

  test(
    'PDF valid dan transaksi yang banyak terbagi ke beberapa halaman',
    () async {
      final bytes = await FinanceReportExporter.encode(
        report([
          for (var i = 0; i < 120; i++)
            row(
              '$i',
              'expense',
              24000,
              note: 'Kopi café dan makan siang, catatan transaksi nomor $i.',
            ),
        ]),
        FinanceReportFormat.pdf,
      );
      final source = latin1.decode(bytes);
      if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
        final folder = Directory('build/report-previews');
        await folder.create(recursive: true);
        await File('${folder.path}/laporan-contoh.pdf').writeAsBytes(bytes);
      }
      expect(source.startsWith('%PDF-'), isTrue);
      expect(source.trimRight().endsWith('%%EOF'), isTrue);
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(source).length,
        greaterThan(1),
      );
    },
  );
}
