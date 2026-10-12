import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/transactions/domain/usecases/calculate_balance_history.dart';

void main() {
  test('bulan berjalan mulai tanggal 1, bukan 30 hari terakhir', () {
    final points = BalanceHistoryCalculator.currentMonth(
      now: DateTime(2026, 10, 6, 22, 30),
      changes: [
        BalanceChange(occurredAt: DateTime(2026, 9, 1), amount: 1000),
        BalanceChange(occurredAt: DateTime(2026, 9, 30), amount: -200),
        BalanceChange(occurredAt: DateTime(2026, 10, 1), amount: 50),
        BalanceChange(occurredAt: DateTime(2026, 10, 6, 22), amount: -100),
      ],
    );
    expect(points.length, 6);
    expect(points.first.date, DateTime(2026, 10, 1));
    expect(points.first.balance, 850);
    expect(points.map((p) => p.balance), [850, 850, 850, 850, 850, 750]);
    expect(points.last.date, DateTime(2026, 10, 6));
  });

  for (final monthEnd in [
    DateTime(2026, 1, 31),
    DateTime(2026, 2, 28),
    DateTime(2028, 2, 29),
    DateTime(2026, 4, 30),
  ]) {
    test('panjang bulan mengikuti kalender: $monthEnd', () {
      final points = BalanceHistoryCalculator.currentMonth(
        now: monthEnd,
        changes: const [],
      );
      expect(points.length, monthEnd.day);
      expect(points.first.date, DateTime(monthEnd.year, monthEnd.month));
      expect(points.last.date, monthEnd);
      expect(points.every((point) => point.balance == 0), isTrue);
    });
  }

  test(
    'tanggal 1 tetap memiliki satu titik, dengan saldo bulan sebelumnya',
    () {
      final points = BalanceHistoryCalculator.currentMonth(
        now: DateTime(2027, 1, 1),
        changes: [
          BalanceChange(occurredAt: DateTime(2026, 12, 31), amount: 250),
        ],
      );
      expect(points.single.date, DateTime(2027, 1, 1));
      expect(points.single.balance, 250);
    },
  );

  test('timestamp UTC dikelompokkan sesuai tanggal lokal', () {
    final local = DateTime(2026, 10, 1, 0, 30);
    final points = BalanceHistoryCalculator.currentMonth(
      now: DateTime(2026, 10, 2),
      changes: [BalanceChange(occurredAt: local.toUtc(), amount: 100)],
    );
    expect(points.map((point) => point.balance), [100, 100]);
  });

  test('entri mendatang tetap cocok dengan saldo tanpa titik proyeksi', () {
    final points = BalanceHistoryCalculator.currentMonth(
      now: DateTime(2026, 10, 6),
      changes: [
        BalanceChange(occurredAt: DateTime(2026, 10, 1), amount: 100),
        BalanceChange(occurredAt: DateTime(2026, 10, 20), amount: 200),
      ],
    );
    expect(points.length, 6);
    expect(points.first.balance, 100);
    expect(points.last.balance, 300);
  });

  test('saldo transfer antar aset tidak mengubah saldo gabungan', () {
    final date = DateTime(2026, 10, 3);
    final points = BalanceHistoryCalculator.currentMonth(
      now: DateTime(2026, 10, 6),
      changes: [
        BalanceChange(occurredAt: DateTime(2026, 9, 1), amount: 1000),
        BalanceChange(occurredAt: date, amount: -300),
        BalanceChange(occurredAt: date, amount: 300),
      ],
    );
    expect(points.every((point) => point.balance == 1000), isTrue);
  });
}
