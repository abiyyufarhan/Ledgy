import '../../../transactions/domain/entities/transaction.dart';

enum RecurrenceFrequency { daily, weekly, monthly }

class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    required this.frequency,
    required this.interval,
    required this.nextOccurrenceAt,
    this.toAccountId,
    this.categoryId,
    this.note,
    this.isActive = true,
    this.deletedAt,
  }) : assert(amount >= 0),
       assert(interval > 0);

  final String id;
  final TransactionType type;
  final int amount;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String? note;
  final RecurrenceFrequency frequency;
  final int interval;
  final DateTime nextOccurrenceAt;
  final bool isActive;
  final DateTime? deletedAt;

  bool get canGenerate => isActive && deletedAt == null;
}
