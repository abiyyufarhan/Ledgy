import '../../../recurring/domain/entities/recurring_rule.dart';
import '../entities/transaction.dart';

class RecurringTransactionFactory {
  const RecurringTransactionFactory._();

  static LedgerTransaction create({
    required RecurringRule rule,
    required String transactionId,
    required DateTime occurredAt,
  }) {
    if (!rule.canGenerate) {
      throw StateError('Aturan berulang tidak aktif atau telah dihapus.');
    }
    return LedgerTransaction(
      id: transactionId,
      type: rule.type,
      amount: rule.amount,
      accountId: rule.accountId,
      toAccountId: rule.toAccountId,
      categoryId: rule.categoryId,
      note: rule.note,
      occurredAt: occurredAt.toUtc(),
    );
  }

  static DateTime nextOccurrence(RecurringRule rule) {
    final value = rule.nextOccurrenceAt.toUtc();
    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        return value.add(Duration(days: rule.interval));
      case RecurrenceFrequency.weekly:
        return value.add(Duration(days: 7 * rule.interval));
      case RecurrenceFrequency.monthly:
        final target = DateTime.utc(value.year, value.month + rule.interval);
        final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
        return DateTime.utc(
          target.year,
          target.month,
          value.day.clamp(1, lastDay),
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
          value.microsecond,
        );
    }
  }
}
