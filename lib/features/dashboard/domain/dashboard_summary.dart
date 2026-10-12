import '../../../core/database/app_database.dart';
import '../../local/data/local_finance_repository.dart';
import '../../reports/domain/finance_report.dart';

enum CashflowPeriod {
  allTime('Keseluruhan'),
  weekly('Mingguan'),
  monthly('Bulanan'),
  yearly('Tahunan');

  const CashflowPeriod(this.label);
  final String label;
}

class CashflowPoint {
  const CashflowPoint(
    this.label,
    this.income,
    this.expense, {
    required this.incomeCount,
    required this.expenseCount,
  });
  final String label;
  final int income;
  final int expense;
  final int incomeCount;
  final int expenseCount;
  bool get hasIncome => incomeCount > 0;
  bool get hasExpense => expenseCount > 0;
}

/// All dashboard views use the same active ledger and local calendar boundaries.
class DashboardSummary {
  DashboardSummary(this.snapshot, this.month);
  final FinanceSnapshot snapshot;
  final DateTime month;

  List<Account> get accounts =>
      snapshot.accounts.where((a) => a.deletedAt == null).toList();
  List<Transaction> get transactions =>
      snapshot.transactions.where((t) => t.deletedAt == null).toList();
  MonthlyCashflow get cashflow => FinanceReports.month(snapshot.ledger, month);
  double? get savingsRatio =>
      cashflow.income == 0 ? null : cashflow.net / cashflow.income;

  Map<String, int> get balances {
    final result = {for (final a in accounts) a.id: a.initialBalance};
    for (final t in transactions) {
      if (result.containsKey(t.accountId)) {
        result[t.accountId] =
            result[t.accountId]! + (t.type == 'income' ? t.amount : -t.amount);
      }
      if (t.type == 'transfer' && result.containsKey(t.toAccountId)) {
        result[t.toAccountId!] = result[t.toAccountId!]! + t.amount;
      }
    }
    return result;
  }

  int get netWorth => balances.values.fold(0, (a, b) => a + b);

  List<Transaction> recent(String query) {
    final normalized = query.trim().toLowerCase();
    final names = {for (final a in snapshot.accounts) a.id: a.name};
    final result =
        transactions.where((t) {
          if (normalized.isEmpty) return inLocalMonth(t.occurredAt, month);
          return '${t.note ?? ''} ${snapshot.categoryNames[t.categoryId] ?? ''} '
                  '${names[t.accountId] ?? ''} ${names[t.toAccountId] ?? ''} '
                  '${t.amount} ${switch (t.type) {
                    'income' => 'Pemasukan',
                    'expense' => 'Pengeluaran',
                    _ => 'Transfer',
                  }}'
              .toLowerCase()
              .contains(normalized);
        }).toList()..sort((a, b) {
          final date = b.occurredAt.compareTo(a.occurredAt);
          return date != 0 ? date : a.id.compareTo(b.id);
        });
    return result;
  }

  List<CashflowPoint> get weekly => trend(CashflowPeriod.weekly);

  List<CashflowPoint> trend(CashflowPeriod period) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final activeTransactions = transactions;
    final cashTransactions = activeTransactions
        .where((t) => t.type == 'income' || t.type == 'expense')
        .toList();
    DateTime? firstDay, lastDay;
    if (period == CashflowPeriod.allTime) {
      if (activeTransactions.isEmpty) return [];
      for (final t in activeTransactions) {
        final day = _calendarDay(t.occurredAt);
        if (firstDay == null || day.isBefore(firstDay)) firstDay = day;
        if (lastDay == null || day.isAfter(lastDay)) lastDay = day;
      }
    }
    var firstYear = month.year;
    if (period == CashflowPeriod.yearly) {
      for (final t in cashTransactions) {
        final year = t.occurredAt.toLocal().year;
        if (year < firstYear) firstYear = year;
      }
    }
    final count = switch (period) {
      CashflowPeriod.allTime => lastDay!.difference(firstDay!).inDays + 1,
      CashflowPeriod.weekly => (days / 7).ceil(),
      CashflowPeriod.monthly => 12,
      CashflowPeriod.yearly => month.year - firstYear + 1,
    };
    final income = List.filled(count, 0);
    final expense = List.filled(count, 0);
    final incomeCount = List.filled(count, 0);
    final expenseCount = List.filled(count, 0);
    for (final t in cashTransactions) {
      final local = t.occurredAt.toLocal();
      if (period == CashflowPeriod.weekly) {
        if (!inLocalMonth(local, month)) continue;
      } else if (period == CashflowPeriod.monthly) {
        if (local.year != month.year) continue;
      } else if (period == CashflowPeriod.yearly && local.year > month.year) {
        continue;
      }
      final index = switch (period) {
        CashflowPeriod.allTime => _calendarDay(
          t.occurredAt,
        ).difference(firstDay!).inDays,
        CashflowPeriod.weekly => (local.day - 1) ~/ 7,
        CashflowPeriod.monthly => local.month - 1,
        CashflowPeriod.yearly => local.year - firstYear,
      };
      if (t.type == 'income') {
        income[index] += t.amount;
        incomeCount[index]++;
      } else {
        expense[index] += t.amount;
        expenseCount[index]++;
      }
    }
    const monthLabels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return [
      for (var i = 0; i < count; i++)
        CashflowPoint(
          switch (period) {
            CashflowPeriod.allTime => _dateLabel(
              firstDay!.add(Duration(days: i)),
            ),
            CashflowPeriod.weekly => 'M${i + 1}',
            CashflowPeriod.monthly => monthLabels[i],
            CashflowPeriod.yearly => '${firstYear + i}',
          },
          income[i],
          expense[i],
          incomeCount: incomeCount[i],
          expenseCount: expenseCount[i],
        ),
    ];
  }

  // Calendar-day offsets stay correct across timezone/DST changes.
  static DateTime _calendarDay(DateTime date) {
    final local = date.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  static String _dateLabel(DateTime day) =>
      '${day.day}/${day.month}/${(day.year % 100).toString().padLeft(2, '0')}';

  List<BudgetProgress> get budgets => [
    for (final b in snapshot.budgets)
      if (b.deletedAt == null && inLocalMonth(b.monthStart, month))
        BudgetProgress(
          b,
          snapshot.categoryNames[b.categoryId] ?? 'Lainnya',
          FinanceReports.budgetSpent(
            category: snapshot.categoryNames[b.categoryId] ?? 'Lainnya',
            month: month,
            items: snapshot.ledger,
            categoryNames: snapshot.categoryNames,
          ),
        ),
  ];
}
