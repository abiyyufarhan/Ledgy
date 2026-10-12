import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../budgets/domain/usecases/budget_alert_policy.dart';
import '../../recurring/domain/usecases/recurring_schedule.dart';
import '../../recurring/domain/recurring_occurrence_id.dart';
import '../../reports/domain/finance_report.dart';
import '../../transactions/domain/entities/transaction.dart';

LedgerTransaction ledgerTransaction(Transaction t) => LedgerTransaction(
  id: t.id,
  type: TransactionType.values.byName(t.type),
  amount: t.amount,
  accountId: t.accountId,
  toAccountId: t.toAccountId,
  categoryId: t.categoryId,
  note: t.note,
  occurredAt: t.occurredAt,
  deletedAt: t.deletedAt,
);

class FinanceSnapshot {
  const FinanceSnapshot(
    this.accounts,
    this.categories,
    this.transactions,
    this.budgets,
    this.rules,
  );
  final List<Account> accounts;
  final List<Category> categories;
  final List<Transaction> transactions;
  final List<Budget> budgets;
  final List<RecurringRule> rules;
  List<LedgerTransaction> get ledger =>
      transactions.map(ledgerTransaction).toList();
  Map<String, String> get categoryNames => {
    for (final c in categories) c.id: c.name,
  };
}

class BudgetProgress {
  const BudgetProgress(this.budget, this.category, this.spent);
  final Budget budget;
  final String category;
  final int spent;
}

typedef BudgetNotifier = Future<bool> Function(
  BudgetProgress progress,
  int threshold,
);

class LocalFinanceRepository {
  LocalFinanceRepository(this.db);
  final AppDatabase db;

  Future<FinanceSnapshot> snapshot() async => FinanceSnapshot(
    await db.select(db.accounts).get(),
    await db.select(db.categories).get(),
    await db.select(db.transactions).get(),
    await db.select(db.budgets).get(),
    await db.select(db.recurringRules).get(),
  );

  Stream<List<RecurringRule>> watchRules() => (db.select(
    db.recurringRules,
  )..where((r) => r.deletedAt.isNull())).watch();

  Future<String?> state(String key) async =>
      (await db
              .customSelect(
                'SELECT value FROM ledgy_local_state WHERE key = ?',
                variables: [Variable(key)],
              )
              .getSingleOrNull())
          ?.read<String>('value');
  Future<void> setState(String key, String value) => db.customStatement(
    'INSERT INTO ledgy_local_state(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );

  Future<String> ensureCategory(String name, String kind) async {
    final canonical = canonicalCategory(name);
    final categories = await (db.select(
      db.categories,
    )..where((c) => c.deletedAt.isNull() & c.kind.equals(kind))).get();
    for (final category in categories) {
      if (canonicalCategory(category.name) == canonical) return category.id;
    }
    final now = DateTime.now().toUtc();
    final id = const Uuid().v4();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            name: canonical,
            kind: Value(kind),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> saveBudget(String category, int amount, DateTime month) async {
    if (amount <= 0) throw ArgumentError('Anggaran harus lebih dari nol.');
    await db.transaction(() async {
      final categoryId = await ensureCategory(category, 'expense');
      final rows =
          await (db.select(db.budgets)..where(
                (b) => b.deletedAt.isNull() & b.categoryId.equals(categoryId),
              ))
              .get();
      final matches = rows.where((b) => inLocalMonth(b.monthStart, month));
      final now = DateTime.now().toUtc();
      if (matches.isNotEmpty) {
        await (db.update(
          db.budgets,
        )..where((b) => b.id.equals(matches.first.id))).write(
          BudgetsCompanion(
            amount: Value(amount),
            updatedAt: Value(now),
            isDirty: const Value(true),
          ),
        );
      } else {
        await db
            .into(db.budgets)
            .insert(
              BudgetsCompanion.insert(
                id: const Uuid().v4(),
                categoryId: categoryId,
                amount: amount,
                monthStart: DateTime(month.year, month.month).toUtc(),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
  }

  Future<void> archiveBudget(String id) =>
      db.budgetsDao.softDelete(id, DateTime.now().toUtc());

  List<BudgetProgress> budgetProgress(FinanceSnapshot s, DateTime month) => [
    for (final b in s.budgets)
      if (b.deletedAt == null && inLocalMonth(b.monthStart, month))
        BudgetProgress(
          b,
          s.categoryNames[b.categoryId] ?? 'Lainnya',
          FinanceReports.budgetSpent(
            category: s.categoryNames[b.categoryId] ?? 'Lainnya',
            month: month,
            items: s.ledger,
            categoryNames: s.categoryNames,
          ),
        ),
  ];

  /// Persisted thresholds survive app restarts. Delivery must succeed before
  /// the marker is saved; denied notification permission can be retried later.
  Future<void> checkBudgets(DateTime now, BudgetNotifier notify) async {
    final s = await snapshot();
    for (final progress in budgetProgress(s, now.toLocal())) {
      await db.transaction(() async {
        await setState('budget:lock', now.toUtc().toIso8601String());
        final key =
            'budget:${progress.budget.id}:${now.toLocal().year}-${now.toLocal().month}';
        final sent = <int>{};
        for (final threshold in [80, 100]) {
          if (await state('$key:$threshold') != null) sent.add(threshold);
        }
        final next = BudgetAlertPolicy.nextThreshold(
          budgeted: progress.budget.amount,
          spent: progress.spent,
          sent: sent,
        );
        if (next != null && await notify(progress, next)) {
          await setState('$key:$next', 'sent');
        }
      });
    }
  }

  Future<void> saveRule({
    required String type,
    required int amount,
    required String accountId,
    String? categoryId,
    String? note,
    required String frequency,
    required int interval,
    required DateTime next,
  }) async {
    if (!['income', 'expense'].contains(type) ||
        amount <= 0 ||
        interval <= 0 ||
        !['daily', 'weekly', 'monthly'].contains(frequency)) {
      throw ArgumentError('Jadwal transaksi tidak valid.');
    }
    await db.transaction(() async {
      final account =
          await (db.select(db.accounts)
                ..where((a) => a.id.equals(accountId) & a.deletedAt.isNull()))
              .getSingleOrNull();
      final category =
          await (db.select(db.categories)..where(
                (c) =>
                    c.id.equals(categoryId ?? '') &
                    c.deletedAt.isNull() &
                    c.kind.equals(type),
              ))
              .getSingleOrNull();
      if (account == null || category == null) {
        throw ArgumentError('Aset atau kategori tidak valid.');
      }
      final now = DateTime.now().toUtc();
      final id = const Uuid().v4();
      await db
          .into(db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              id: id,
              type: type,
              amount: amount,
              accountId: accountId,
              categoryId: Value(categoryId),
              note: Value(note),
              frequency: frequency,
              interval: Value(interval),
              nextOccurrenceAt: next.toUtc(),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await setState('anchor:$id', '${next.toLocal().day}');
    });
  }

  Future<void> toggleRule(String id, bool active) async {
    await (db.update(db.recurringRules)..where((r) => r.id.equals(id))).write(
      RecurringRulesCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now().toUtc()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> archiveRule(String id) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.recurringRules)..where((r) => r.id.equals(id))).write(
      RecurringRulesCompanion(
        deletedAt: Value(now),
        isActive: const Value(false),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  }

  /// Generation and schedule advancement are a single SQLite transaction.
  /// A second foreground/background runner cannot generate the same date twice.
  Future<int> generateDue(DateTime now) => db.transaction(() async {
    // Acquire SQLite's write lock before reading, including separate isolates.
    await setState('recurring:lock', now.toUtc().toIso8601String());
    var count = 0;
    final rules = await (db.select(
      db.recurringRules,
    )..where((r) => r.deletedAt.isNull() & r.isActive.equals(true))).get();
    final accounts = await (db.select(
      db.accounts,
    )..where((a) => a.deletedAt.isNull())).get();
    for (final rule in rules) {
      if (!accounts.any((a) => a.id == rule.accountId)) continue;
      var next = rule.nextOccurrenceAt.toLocal();
      final anchor =
          int.tryParse(await state('anchor:${rule.id}') ?? '') ?? next.day;
      await setState('anchor:${rule.id}', '$anchor');
      // Bounded catch-up: remaining dates are processed on the next run.
      final due = RecurringSchedule.due(
        next: next,
        now: now.toLocal(),
        frequency: rule.frequency,
        interval: rule.interval,
        anchorDay: anchor,
      );
      for (final date in due.dates) {
        final key = 'occurrence:${rule.id}:${date.toUtc().toIso8601String()}';
        if (await state(key) != null) continue;
        final id = recurringOccurrenceId(rule.id, date);
        final existing = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (existing != null) {
          await setState(key, id);
          continue;
        }
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: id,
                type: rule.type,
                amount: rule.amount,
                accountId: rule.accountId,
                toAccountId: Value(rule.toAccountId),
                categoryId: Value(rule.categoryId),
                note: Value(rule.note),
                occurredAt: date.toUtc(),
                createdAt: now.toUtc(),
                updatedAt: now.toUtc(),
              ),
            );
        await setState(key, id);
        count++;
      }
      if (due.dates.isNotEmpty) {
        await (db.update(
          db.recurringRules,
        )..where((r) => r.id.equals(rule.id))).write(
          RecurringRulesCompanion(
            nextOccurrenceAt: Value(due.next.toUtc()),
            updatedAt: Value(now.toUtc()),
            isDirty: const Value(true),
          ),
        );
      }
    }
    return count;
  });
}
