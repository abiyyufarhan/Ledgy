import '../../transactions/domain/entities/transaction.dart';

String canonicalCategory(String name) {
  final parts = name.split('•').map((part) => part.trim()).toList();
  if (const [
    'makanan',
    'makanan & minuman',
  ].contains(parts.first.toLowerCase())) {
    parts[0] = 'Makan & Minum';
  }
  if (parts.first.toLowerCase() == 'transport') parts[0] = 'Transportasi';
  for (var i = 1; i < parts.length; i++) {
    if (RegExp(
      r'^cafe\s*/\s*warkop$',
      caseSensitive: false,
    ).hasMatch(parts[i])) {
      parts[i] = 'Cafe / Warkop';
    }
  }
  return parts.join(' • ');
}

String categoryParent(String name) =>
    canonicalCategory(name).split('•').first.trim();

bool inLocalMonth(DateTime date, DateTime month) {
  final local = date.toLocal();
  return local.year == month.year && local.month == month.month;
}

class MonthlyCashflow {
  const MonthlyCashflow(this.month, this.income, this.expense);
  final DateTime month;
  final int income;
  final int expense;
  int get net => income - expense;
}

abstract final class FinanceReports {
  static MonthlyCashflow month(
    Iterable<LedgerTransaction> items,
    DateTime month,
  ) {
    var income = 0;
    var expense = 0;
    for (final item in items) {
      if (!item.isActive || !inLocalMonth(item.occurredAt, month)) continue;
      if (item.type == TransactionType.income) income += item.amount;
      if (item.type == TransactionType.expense) expense += item.amount;
    }
    return MonthlyCashflow(month, income, expense);
  }

  static List<MonthlyCashflow> sixMonths(
    Iterable<LedgerTransaction> items,
    DateTime lastMonth,
  ) => [
    for (var i = 5; i >= 0; i--)
      month(items, DateTime(lastMonth.year, lastMonth.month - i)),
  ];

  static Map<String, int> categoryTotals(
    Iterable<LedgerTransaction> items,
    DateTime month,
    Map<String, String> categoryNames,
  ) {
    final totals = <String, int>{};
    for (final item in items) {
      if (!item.isActive ||
          item.type != TransactionType.expense ||
          !inLocalMonth(item.occurredAt, month)) {
        continue;
      }
      final name = categoryParent(categoryNames[item.categoryId] ?? 'Lainnya');
      totals[name] = (totals[name] ?? 0) + item.amount;
    }
    return totals;
  }

  /// A parent budget includes all its subcategories; a subcategory budget is
  /// exact. This mirrors the grouping used by Ledgy's analysis page.
  static int budgetSpent({
    required String category,
    required DateTime month,
    required Iterable<LedgerTransaction> items,
    required Map<String, String> categoryNames,
  }) {
    final wanted = canonicalCategory(category);
    return items
        .where((item) {
          if (!item.isActive ||
              item.type != TransactionType.expense ||
              !inLocalMonth(item.occurredAt, month)) {
            return false;
          }
          final actual = canonicalCategory(
            categoryNames[item.categoryId] ?? '',
          );
          return actual == wanted ||
              (!wanted.contains('•') && categoryParent(actual) == wanted);
        })
        .fold(0, (sum, item) => sum + item.amount);
  }
}
