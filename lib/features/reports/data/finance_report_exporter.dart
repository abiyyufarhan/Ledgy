import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/database/app_database.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../transactions/domain/transaction_period.dart';
import '../domain/finance_report.dart';

enum FinanceReportFormat {
  pdf('PDF', 'pdf', 'application/pdf'),
  xlsx(
    'Excel',
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );

  const FinanceReportFormat(this.label, this.extension, this.mimeType);
  final String label, extension, mimeType;
}

/// Captures the displayed rows, so changes during a save dialog cannot change
/// which transactions the user chose to download.
class TransactionReport {
  TransactionReport({
    required List<Transaction> transactions,
    required List<Account> accounts,
    required List<Category> categories,
    required this.date,
    required this.period,
  }) : transactions = List.unmodifiable(
         transactions.where(
           (t) => t.deletedAt == null && period.contains(t.occurredAt, date),
         ),
       ),
       accountNames = {for (final a in accounts) a.id: a.name},
       categoryNames = {
         for (final c in categories) c.id: canonicalCategory(c.name),
       };

  final List<Transaction> transactions;
  final Map<String, String> accountNames, categoryNames;
  final DateTime date;
  final TransactionPeriod period;
  int total(String type) => transactions
      .where((t) => t.type == type)
      .fold(0, (sum, t) => sum + t.amount);
  int get income => total('income');
  int get expense => total('expense');
  String get title => '${period.label} - ${period.title(date)}';
  String fileName(FinanceReportFormat format) =>
      'ledgy-laporan-${period.name}-${period.fileDate(date)}.${format.extension}';
}

abstract final class FinanceReportExporter {
  static const _headers = [
    'Tanggal',
    'Tipe',
    'Akun',
    'Akun tujuan',
    'Kategori',
    'Catatan',
    'Jumlah (Rp)',
  ];

  static String _type(String type) => switch (type) {
    'income' => 'Pemasukan',
    'expense' => 'Pengeluaran',
    _ => 'Transfer',
  };

  static List<String> _row(Transaction t, TransactionReport report) => [
    DateFormat('dd/MM/yyyy HH:mm').format(t.occurredAt.toLocal()),
    _type(t.type),
    report.accountNames[t.accountId] ?? t.accountId,
    t.recipientName != null
        ? '${t.recipientName} • ${t.recipientAccount}'
        : report.accountNames[t.toAccountId] ?? '',
    report.categoryNames[t.categoryId] ?? '',
    t.note ?? '',
    formatRupiah(t.amount),
  ];

  static Future<Uint8List> encode(
    TransactionReport report,
    FinanceReportFormat format,
  ) async => switch (format) {
    FinanceReportFormat.pdf => _pdf(report),
    FinanceReportFormat.xlsx => _xlsx(report),
  };

  static Uint8List _xlsx(TransactionReport report) {
    final book = xlsx.Excel.createExcel();
    book.rename('Sheet1', 'Ringkasan');
    final summary = book['Ringkasan'];
    void summaryRow(String label, xlsx.CellValue value) =>
        summary.appendRow([xlsx.TextCellValue(label), value]);
    summaryRow('Laporan Keuangan Ledgy', xlsx.TextCellValue(report.title));
    summaryRow(
      'Jumlah transaksi',
      xlsx.IntCellValue(report.transactions.length),
    );
    summaryRow('Pemasukan (Rp)', xlsx.IntCellValue(report.income));
    summaryRow('Pengeluaran (Rp)', xlsx.IntCellValue(report.expense));
    summaryRow(
      'Selisih (Rp)',
      xlsx.IntCellValue(report.income - report.expense),
    );
    summaryRow(
      'Cakupan',
      xlsx.TextCellValue(
        'Transaksi yang ditampilkan sesuai periode dan filter.',
      ),
    );
    summary.setColumnWidth(0, 30);
    summary.setColumnWidth(1, 65);

    final sheet = book['Transaksi'];
    sheet.appendRow(_headers.map(xlsx.TextCellValue.new).toList());
    for (final t in report.transactions) {
      final values = _row(t, report);
      // Text cells remain text, including notes beginning with =, +, - or @.
      sheet.appendRow([
        for (final value in values.take(6)) xlsx.TextCellValue(value),
        xlsx.IntCellValue(t.amount),
      ]);
    }
    for (var column = 0; column < _headers.length; column++) {
      sheet.setColumnWidth(column, column == 5 ? 45 : 25);
      sheet
          .cell(
            xlsx.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
          )
          .cellStyle = xlsx.CellStyle(
        bold: true,
      );
    }
    return Uint8List.fromList(book.encode()!);
  }

  static Future<Uint8List> _pdf(TransactionReport report) async {
    final regularFont = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final boldFont = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final document = pw.Document(
      title: 'Laporan Keuangan Ledgy',
      author: 'Ledgy',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        maxPages: report.transactions.length + 2,
        theme: pw.ThemeData.withFont(
          base: pw.Font.ttf(regularFont),
          bold: pw.Font.ttf(boldFont),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Halaman ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => [
          pw.Text(
            'Laporan Keuangan Ledgy',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(report.title),
          pw.SizedBox(height: 12),
          pw.Text(
            'Pemasukan: ${formatRupiah(report.income)}    Pengeluaran: ${formatRupiah(report.expense)}    Selisih: ${formatRupiah(report.income - report.expense)}',
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '${report.transactions.length} transaksi yang ditampilkan sesuai periode dan filter.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: _headers,
            data: [for (final t in report.transactions) _row(t, report)],
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(5),
            cellAlignments: {6: pw.Alignment.centerRight},
            columnWidths: {
              0: const pw.FlexColumnWidth(1.3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1.5),
              5: const pw.FlexColumnWidth(2),
              6: const pw.FlexColumnWidth(1.2),
            },
          ),
        ],
      ),
    );
    return document.save();
  }
}
