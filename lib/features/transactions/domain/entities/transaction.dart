enum TransactionType { income, expense, transfer }

class LedgerTransaction {
  const LedgerTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    required this.occurredAt,
    this.toAccountId,
    this.categoryId,
    this.note,
    this.deletedAt,
  }) : assert(amount >= 0);

  final String id;
  final TransactionType type;
  final int amount;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String? note;
  final DateTime occurredAt;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;
}
