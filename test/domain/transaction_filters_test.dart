import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/reports/domain/finance_report.dart';
import 'package:ledgy/features/transactions/domain/entities/transaction.dart';
import 'package:ledgy/features/transactions/domain/transaction_filters.dart';
import 'package:ledgy/features/transactions/domain/transaction_period.dart';

void main() {
  final month = DateTime(2026, 10);
  const names = {
    'cafe': 'Makanan & Minuman • Cafe /Warkop',
    'food': 'Makan & Minum • Restoran',
    'bill': 'Tagihan • Listrik',
    'salary': 'Gaji',
  };
  LedgerTransaction t(
    String id, {
    TransactionType type = TransactionType.expense,
    String? category = 'cafe',
    String account = 'cash',
    String? to,
    DateTime? date,
    DateTime? deleted,
  }) => LedgerTransaction(
    id: id,
    type: type,
    amount: type == TransactionType.transfer ? 500 : 100,
    accountId: account,
    toAccountId: to,
    categoryId: category,
    occurredAt: date ?? DateTime(2026, 10, 1, 0, 15).toUtc(),
    deletedAt: deleted,
  );
  bool matches(TransactionFilters f, LedgerTransaction value) =>
      f.matches(value, month: month, categoryNames: names);

  test(
    'semua mencakup transfer, tidak termasuk bulan lain atau soft-delete',
    () {
      const filters = TransactionFilters();
      expect(
        matches(filters, t('transfer', type: TransactionType.transfer)),
        isTrue,
      );
      expect(
        matches(filters, t('old', date: DateTime(2026, 9, 30, 23, 59))),
        isFalse,
      );
      expect(matches(filters, t('next', date: DateTime(2026, 11, 1))), isFalse);
      expect(matches(filters, t('deleted', deleted: month)), isFalse);
    },
  );
  test('pemasukan/pengeluaran dan batas bulan menggunakan waktu lokal', () {
    expect(
      matches(const TransactionFilters(type: 'expense'), t('expense')),
      isTrue,
    );
    expect(
      matches(const TransactionFilters(type: 'income'), t('expense')),
      isFalse,
    );
    expect(
      matches(
        const TransactionFilters(type: 'income'),
        t('salary', type: TransactionType.income),
      ),
      isTrue,
    );
    expect(
      matches(
        const TransactionFilters(type: 'expense'),
        t('transfer', type: TransactionType.transfer),
      ),
      isFalse,
    );
  });
  test(
    'kategori induk mencakup semua subkategori dan normalisasi nama lama',
    () {
      const root = TransactionFilters(categoryName: 'Makan & Minum');
      expect(matches(root, t('cafe')), isTrue);
      expect(matches(root, t('food', category: 'food')), isTrue);
      expect(matches(root, t('bill', category: 'bill')), isFalse);
      expect(matches(root, t('none', category: null)), isFalse);
      const child = TransactionFilters(
        categoryName: 'Makan & Minum • Cafe / Warkop',
      );
      expect(matches(child, t('cafe')), isTrue);
      expect(matches(child, t('food', category: 'food')), isFalse);
    },
  );
  test('akun dapat menjadi sumber atau tujuan transfer', () {
    const filters = TransactionFilters(accountId: 'bank');
    expect(
      matches(
        filters,
        t('incoming', type: TransactionType.transfer, to: 'bank'),
      ),
      isTrue,
    );
    expect(
      matches(
        filters,
        t(
          'outgoing',
          type: TransactionType.transfer,
          account: 'bank',
          to: 'cash',
        ),
      ),
      isTrue,
    );
    expect(matches(filters, t('other')), isFalse);
    expect(
      matches(
        const TransactionFilters(
          type: 'expense',
          categoryName: 'Makan & Minum',
          accountId: 'bank',
        ),
        t('combined', account: 'bank'),
      ),
      isTrue,
    );
  });
  test('ringkasan bulanan mengabaikan transfer dan transaksi dihapus', () {
    final totals = FinanceReports.month([
      t('salary', type: TransactionType.income, category: 'salary'),
      t('expense'),
      t('transfer', type: TransactionType.transfer),
      t('deleted', deleted: month),
      t('old', date: DateTime(2026, 9)),
    ], month);
    expect(totals.income, 100);
    expect(totals.expense, 100);
  });

  test(
    'batas hari/bulan/tahun memakai waktu lokal dan tetap menerapkan filter',
    () {
      final selected = DateTime(2026, 10, 7);
      bool periodMatch(DateTime date, TransactionPeriod period) =>
          const TransactionFilters(type: 'expense', accountId: 'cash').matches(
            t('row', date: date.toUtc()),
            month: selected,
            period: period,
            categoryNames: names,
          );
      expect(
        periodMatch(DateTime(2026, 10, 7), TransactionPeriod.daily),
        isTrue,
      );
      expect(
        periodMatch(DateTime(2026, 10, 7, 23, 59), TransactionPeriod.daily),
        isTrue,
      );
      expect(
        periodMatch(DateTime(2026, 10, 8), TransactionPeriod.daily),
        isFalse,
      );
      expect(
        periodMatch(DateTime(2026, 10, 6, 23, 59), TransactionPeriod.daily),
        isFalse,
      );
      expect(
        periodMatch(DateTime(2026, 1, 1), TransactionPeriod.yearly),
        isTrue,
      );
      expect(
        periodMatch(DateTime(2026, 12, 31, 23, 59), TransactionPeriod.yearly),
        isTrue,
      );
      expect(
        periodMatch(DateTime(2025, 12, 31), TransactionPeriod.yearly),
        isFalse,
      );
      expect(
        periodMatch(DateTime(2027, 1, 1), TransactionPeriod.yearly),
        isFalse,
      );
    },
  );

  test('navigasi periode menangani pergantian tahun dan tanggal kabisat', () {
    expect(
      TransactionPeriod.daily.shift(DateTime(2026, 12, 31), 1),
      DateTime(2027, 1, 1),
    );
    expect(
      TransactionPeriod.daily.shift(DateTime(2026, 1, 1), -1),
      DateTime(2025, 12, 31),
    );
    expect(
      TransactionPeriod.monthly.shift(DateTime(2026, 1, 31), 1),
      DateTime(2026, 2, 28),
    );
    expect(
      TransactionPeriod.monthly.shift(DateTime(2024, 1, 31), 1),
      DateTime(2024, 2, 29),
    );
    expect(
      TransactionPeriod.yearly.shift(DateTime(2024, 2, 29), 1),
      DateTime(2025, 2, 28),
    );
  });
}
