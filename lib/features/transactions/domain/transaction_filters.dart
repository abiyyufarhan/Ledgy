import '../../reports/domain/finance_report.dart';
import '../../categories/domain/category_catalog.dart';
import 'entities/transaction.dart';
import 'transaction_period.dart';

class TransactionFilters {
  const TransactionFilters({this.type, this.categoryName, this.accountId});

  final String? type;

  /// Canonical category name, optionally including " • subcategory".
  final String? categoryName;
  final String? accountId;
  bool get isActive =>
      type != null || categoryName != null || accountId != null;

  bool matches(
    LedgerTransaction transaction, {
    required DateTime month,
    TransactionPeriod period = TransactionPeriod.monthly,
    required Map<String, String> categoryNames,
  }) {
    if (!transaction.isActive ||
        !period.contains(transaction.occurredAt, month)) {
      return false;
    }
    if (type != null && transaction.type.name != type) return false;
    if (accountId != null &&
        transaction.accountId != accountId &&
        transaction.toAccountId != accountId) {
      return false;
    }
    if (categoryName != null) {
      String normalize(String name) => canonicalCategory(
        transaction.type == TransactionType.income
            ? incomeCategoryName(name)
            : name,
      ).toLowerCase();
      final selected = normalize(categoryName!);
      final actual = normalize(categoryNames[transaction.categoryId] ?? '');
      if (actual != selected && !actual.startsWith('$selected • ')) {
        return false;
      }
    }
    return true;
  }
}
