import '../../../accounts/domain/entities/account.dart';
import '../entities/transaction.dart';

class AccountBalanceCalculator {
  const AccountBalanceCalculator._();

  static AccountBalance calculate({
    required String accountId,
    required int initialBalance,
    required Iterable<LedgerTransaction> transactions,
  }) {
    var balance = initialBalance;
    for (final transaction in transactions.where((item) => item.isActive)) {
      switch (transaction.type) {
        case TransactionType.income:
          if (transaction.accountId == accountId) {
            balance += transaction.amount;
          }
        case TransactionType.expense:
          if (transaction.accountId == accountId) {
            balance -= transaction.amount;
          }
        case TransactionType.transfer:
          if (transaction.accountId == accountId) {
            balance -= transaction.amount;
          }
          if (transaction.toAccountId == accountId) {
            balance += transaction.amount;
          }
      }
    }
    return AccountBalance(accountId: accountId, balance: balance);
  }
}
