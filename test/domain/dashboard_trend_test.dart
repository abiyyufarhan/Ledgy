import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/features/dashboard/domain/dashboard_summary.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';

Transaction tx(
  String id,
  String type,
  int amount,
  DateTime date, {
  bool deleted = false,
}) => Transaction(
  id: id,
  type: type,
  amount: amount,
  accountId: 'wallet',
  occurredAt: date,
  createdAt: date,
  updatedAt: date,
  isDirty: false,
  deletedAt: deleted ? date : null,
);

DashboardSummary summary(DateTime month, List<Transaction> transactions) =>
    DashboardSummary(FinanceSnapshot([], [], transactions, [], []), month);

void main() {
  test('keseluruhan dimulai pada transaksi pertama dan mencakup seluruh tanggal aktif', () {
    final data = summary(DateTime(2024, 2), [
      tx('a', 'income', 100, DateTime(2024, 2, 8).toUtc()),
      tx('b', 'income', 50, DateTime(2024, 2, 8, 15).toUtc()),
      tx('c', 'expense', 20, DateTime(2024, 2, 29)),
      tx('d', 'expense', 999, DateTime(2024, 2, 8), deleted: true),
      tx('e', 'transfer', 999, DateTime(2024, 2, 8)),
      tx('f', 'income', 999, DateTime(2024, 3, 1)),
      tx('g', 'income', 999, DateTime(2020), deleted: true),
    ]).trend(CashflowPeriod.allTime);
    expect(data.length, 23);
    expect(data.first.label, '8/2/24');
    expect(data.first.income, 150);
    expect(data.first.incomeCount, 2);
    expect(data.first.hasExpense, isFalse);
    expect(data[1].hasIncome || data[1].hasExpense, isFalse);
    expect(data[21].expense, 20);
    expect(data.last.income, 999);
    expect(data.last.label, '1/3/24');
  });

  test('keseluruhan melintasi tahun, mengikuti transaksi pertama dan mengabaikan bulan pilihan', () {
    final transactions = [
      tx('first', 'transfer', 100, DateTime(2023, 12, 30).toUtc()),
      tx('income', 'income', 20, DateTime(2023, 12, 31).toUtc()),
      tx('last', 'expense', 10, DateTime(2024, 1, 2).toUtc()),
    ];
    final data = summary(
      DateTime(2026, 10),
      transactions,
    ).trend(CashflowPeriod.allTime);
    expect(data.map((p) => p.label), [
      '30/12/23',
      '31/12/23',
      '1/1/24',
      '2/1/24',
    ]);
    expect(data.first.hasIncome || data.first.hasExpense, isFalse);
    expect(data[1].income, 20);
    expect(data.last.expense, 10);
    final earlierMonth = summary(
      DateTime(2020, 1),
      transactions,
    ).trend(CashflowPeriod.allTime);
    expect(earlierMonth.map((p) => p.label), data.map((p) => p.label));
    expect(
      summary(DateTime(2026, 10), []).trend(CashflowPeriod.allTime),
      isEmpty,
    );
  });

  test('mingguan memakai batas tanggal lokal 1–7, 8–14 dan seterusnya', () {
    final data = summary(DateTime(2026, 10), [
      for (final day in [7, 8, 14, 15, 28, 29, 31])
        tx('$day', 'expense', 10, DateTime(2026, 10, day).toUtc()),
    ]).trend(CashflowPeriod.weekly);
    expect(data.map((p) => p.expense), [10, 20, 10, 10, 20]);
    expect(data.map((p) => p.hasIncome), everyElement(isFalse));
    expect(summary(DateTime(2025, 2), []).weekly.length, 4);
  });

  test('bulanan mencakup Januari sampai Desember hanya pada tahun pilihan', () {
    final data = summary(DateTime(2026, 10), [
      tx('a', 'income', 100, DateTime(2026, 1, 1)),
      tx('b', 'expense', 20, DateTime(2026, 12, 31)),
      tx('c', 'income', 999, DateTime(2025, 12, 31)),
      tx('d', 'expense', 999, DateTime(2027, 1, 1)),
    ]).trend(CashflowPeriod.monthly);
    expect(data.length, 12);
    expect(data.first.label, 'Jan');
    expect(data.first.income, 100);
    expect(data.last.label, 'Des');
    expect(data.last.expense, 20);
    expect(data[1].hasIncome || data[1].hasExpense, isFalse);
  });

  test(
    'tahunan memakai riwayat hingga tahun pilihan dan mempertahankan celah',
    () {
      final data = summary(DateTime(2026, 10), [
        tx('a', 'income', 100, DateTime(2023, 12, 31)),
        tx('b', 'expense', 20, DateTime(2025, 1, 1)),
        tx('c', 'income', 30, DateTime(2026, 1, 1)),
        tx('d', 'income', 999, DateTime(2027, 1, 1)),
        tx('e', 'transfer', 999, DateTime(1900)),
        tx('f', 'income', 999, DateTime(1899), deleted: true),
      ]).trend(CashflowPeriod.yearly);
      expect(data.map((p) => p.label), ['2023', '2024', '2025', '2026']);
      expect(data.map((p) => p.income), [100, 0, 0, 30]);
      expect(data[1].hasIncome || data[1].hasExpense, isFalse);
      expect(data[2].expense, 20);
      expect(
        summary(
          DateTime(2026, 10),
          [],
        ).trend(CashflowPeriod.yearly).single.hasIncome,
        isFalse,
      );
    },
  );

  test(
    'transaksi nol yang benar-benar ada dibedakan dari periode tanpa data',
    () {
      final data = summary(DateTime(2026, 10), [
        tx('a', 'income', 0, DateTime(2026, 10, 8)),
      ]).weekly;
      expect(data[1].hasIncome, isTrue);
      expect(data[1].income, 0);
      expect(data.first.hasIncome, isFalse);
    },
  );
}
