import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/budgets/domain/usecases/get_budget_progress.dart';
import 'package:ledgy/features/recurring/domain/entities/recurring_rule.dart';
import 'package:ledgy/features/transactions/domain/entities/transaction.dart';
import 'package:ledgy/features/transactions/domain/usecases/calculate_account_balance.dart';
import 'package:ledgy/features/transactions/domain/usecases/calculate_period_totals.dart';
import 'package:ledgy/features/transactions/domain/usecases/get_recurring_transactions.dart';

LedgerTransaction transaction({
  required String id,
  required TransactionType type,
  required int amount,
  required String accountId,
  required DateTime occurredAt,
  String? toAccountId,
  String? categoryId,
  DateTime? deletedAt,
}) => LedgerTransaction(
  id: id,
  type: type,
  amount: amount,
  accountId: accountId,
  toAccountId: toAccountId,
  categoryId: categoryId,
  occurredAt: occurredAt,
  deletedAt: deletedAt,
);

void main() {
  group('AccountBalanceCalculator', () {
    test(
      'menghitung pemasukan, pengeluaran, dan transfer untuk setiap akun',
      () {
        final transactions = [
          transaction(
            id: 'income',
            type: TransactionType.income,
            amount: 1000,
            accountId: 'cash',
            occurredAt: DateTime.utc(2026, 1, 1),
          ),
          transaction(
            id: 'expense',
            type: TransactionType.expense,
            amount: 300,
            accountId: 'cash',
            occurredAt: DateTime.utc(2026, 1, 2),
          ),
          transaction(
            id: 'out',
            type: TransactionType.transfer,
            amount: 200,
            accountId: 'cash',
            toAccountId: 'bank',
            occurredAt: DateTime.utc(2026, 1, 3),
          ),
          transaction(
            id: 'in',
            type: TransactionType.transfer,
            amount: 50,
            accountId: 'bank',
            toAccountId: 'cash',
            occurredAt: DateTime.utc(2026, 1, 4),
          ),
        ];

        expect(
          AccountBalanceCalculator.calculate(
            accountId: 'cash',
            initialBalance: 100,
            transactions: transactions,
          ).balance,
          650,
        );
        expect(
          AccountBalanceCalculator.calculate(
            accountId: 'bank',
            initialBalance: 0,
            transactions: transactions,
          ).balance,
          150,
        );
      },
    );

    test('mengabaikan transaksi yang di-soft delete', () {
      final deleted = transaction(
        id: 'deleted',
        type: TransactionType.income,
        amount: 500,
        accountId: 'cash',
        occurredAt: DateTime.utc(2026, 1, 1),
        deletedAt: DateTime.utc(2026, 1, 2),
      );

      expect(
        AccountBalanceCalculator.calculate(
          accountId: 'cash',
          initialBalance: 100,
          transactions: [deleted],
        ).balance,
        100,
      );
    });
  });

  group('PeriodTotalsCalculator', () {
    test('mengabaikan transfer dan memisahkan batas pergantian bulan', () {
      final transactions = [
        transaction(
          id: 'jan-income',
          type: TransactionType.income,
          amount: 2000,
          accountId: 'cash',
          occurredAt: DateTime.utc(2026, 1, 31, 23, 59),
        ),
        transaction(
          id: 'jan-expense',
          type: TransactionType.expense,
          amount: 400,
          accountId: 'cash',
          occurredAt: DateTime.utc(2026, 1, 31),
        ),
        transaction(
          id: 'transfer',
          type: TransactionType.transfer,
          amount: 900,
          accountId: 'cash',
          toAccountId: 'bank',
          occurredAt: DateTime.utc(2026, 1, 31),
        ),
        transaction(
          id: 'feb-expense',
          type: TransactionType.expense,
          amount: 600,
          accountId: 'cash',
          occurredAt: DateTime.utc(2026, 2, 1),
        ),
      ];

      final january = PeriodTotalsCalculator.calculate(
        transactions: transactions,
        period: DateRange.month(DateTime.utc(2026, 1, 15)),
      );
      final february = PeriodTotalsCalculator.calculate(
        transactions: transactions,
        period: DateRange.month(DateTime.utc(2026, 2, 15)),
      );

      expect(january.income, 2000);
      expect(january.expense, 400);
      expect(february.income, 0);
      expect(february.expense, 600);
    });
  });

  group('BudgetProgressCalculator', () {
    test('menghitung sisa anggaran kategori dan mengabaikan soft delete', () {
      final transactions = [
        transaction(
          id: 'food',
          type: TransactionType.expense,
          amount: 300,
          accountId: 'cash',
          categoryId: 'food',
          occurredAt: DateTime.utc(2026, 1, 5),
        ),
        transaction(
          id: 'deleted',
          type: TransactionType.expense,
          amount: 50,
          accountId: 'cash',
          categoryId: 'food',
          occurredAt: DateTime.utc(2026, 1, 8),
          deletedAt: DateTime.utc(2026, 1, 9),
        ),
        transaction(
          id: 'other',
          type: TransactionType.expense,
          amount: 100,
          accountId: 'cash',
          categoryId: 'transport',
          occurredAt: DateTime.utc(2026, 1, 9),
        ),
      ];

      final progress = BudgetProgressCalculator.calculate(
        categoryId: 'food',
        budgetedAmount: 500,
        period: DateRange.month(DateTime.utc(2026, 1)),
        transactions: transactions,
      );

      expect(progress.spent, 300);
      expect(progress.remaining, 200);
    });
  });

  group('RecurringTransactionFactory', () {
    test('membuat transaksi dari aturan dan menangani akhir bulan', () {
      final rule = RecurringRule(
        id: 'salary',
        type: TransactionType.income,
        amount: 5000000,
        accountId: 'cash',
        categoryId: 'salary',
        note: 'Gaji bulanan',
        frequency: RecurrenceFrequency.monthly,
        interval: 1,
        nextOccurrenceAt: DateTime.utc(2025, 1, 31, 8),
      );

      final created = RecurringTransactionFactory.create(
        rule: rule,
        transactionId: 'generated',
        occurredAt: rule.nextOccurrenceAt,
      );

      expect(created.id, 'generated');
      expect(created.amount, 5000000);
      expect(created.type, TransactionType.income);
      expect(
        RecurringTransactionFactory.nextOccurrence(rule),
        DateTime.utc(2025, 2, 28, 8),
      );
    });

    test('menolak aturan tidak aktif', () {
      final rule = RecurringRule(
        id: 'inactive',
        type: TransactionType.expense,
        amount: 100,
        accountId: 'cash',
        frequency: RecurrenceFrequency.monthly,
        interval: 1,
        nextOccurrenceAt: DateTime.utc(2026, 1, 1),
        isActive: false,
      );

      expect(
        () => RecurringTransactionFactory.create(
          rule: rule,
          transactionId: 'ignored',
          occurredAt: DateTime.utc(2026, 1, 1),
        ),
        throwsStateError,
      );
    });
  });
}
