import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/usecases/calculate_period_totals.dart';

class BudgetProgress {
  const BudgetProgress({required this.budgeted, required this.spent});

  final int budgeted;
  final int spent;
  int get remaining => budgeted - spent;
}

class BudgetProgressCalculator {
  const BudgetProgressCalculator._();

  static BudgetProgress calculate({
    required String categoryId,
    required int budgetedAmount,
    required DateRange period,
    required Iterable<LedgerTransaction> transactions,
  }) {
    final spent = transactions
        .where(
          (transaction) =>
              transaction.isActive &&
              transaction.type == TransactionType.expense &&
              transaction.categoryId == categoryId &&
              period.contains(transaction.occurredAt.toUtc()),
        )
        .fold<int>(0, (total, transaction) => total + transaction.amount);
    return BudgetProgress(budgeted: budgetedAmount, spent: spent);
  }
}
