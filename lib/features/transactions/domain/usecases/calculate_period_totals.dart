import '../entities/transaction.dart';

class DateRange {
  DateRange({required this.start, required this.end})
    : assert(!end.isBefore(start));

  final DateTime start;
  final DateTime end;

  factory DateRange.month(DateTime date) {
    final utc = date.toUtc();
    return DateRange(
      start: DateTime.utc(utc.year, utc.month),
      end: DateTime.utc(utc.year, utc.month + 1),
    );
  }

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(end);
}

class PeriodTotals {
  const PeriodTotals({required this.income, required this.expense});

  final int income;
  final int expense;
  int get net => income - expense;
}

class PeriodTotalsCalculator {
  const PeriodTotalsCalculator._();

  static PeriodTotals calculate({
    required Iterable<LedgerTransaction> transactions,
    required DateRange period,
  }) {
    var income = 0;
    var expense = 0;
    for (final transaction in transactions) {
      if (!transaction.isActive ||
          !period.contains(transaction.occurredAt.toUtc())) {
        continue;
      }
      switch (transaction.type) {
        case TransactionType.income:
          income += transaction.amount;
        case TransactionType.expense:
          expense += transaction.amount;
        case TransactionType.transfer:
          break;
      }
    }
    return PeriodTotals(income: income, expense: expense);
  }
}
