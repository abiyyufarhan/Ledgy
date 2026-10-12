import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';

mixin SyncColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();
  BoolColumn get isDirty =>
      boolean().named('is_dirty').withDefault(const Constant(true))();
}

class Accounts extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get name => text()();
  IntColumn get initialBalance =>
      integer().named('initial_balance').withDefault(const Constant(0))();
}

class Categories extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get name => text()();
  TextColumn get kind => text().withDefault(const Constant('expense'))();
}

class Transactions extends Table with SyncColumns {
  @override
  String get tableName => 'transactions';

  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get type => text().customConstraint(
    "NOT NULL CHECK (type IN ('income', 'expense', 'transfer'))",
  )();
  IntColumn get amount =>
      integer().customConstraint('NOT NULL CHECK (amount >= 0)')();
  TextColumn get accountId => text().named('account_id')();
  TextColumn get toAccountId => text().named('to_account_id').nullable()();
  TextColumn get recipientName => text().named('recipient_name').nullable()();
  TextColumn get recipientAccount =>
      text().named('recipient_account').nullable()();
  TextColumn get categoryId => text().named('category_id').nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime().named('occurred_at')();
}

/// Local correction hints, intentionally excluded from SyncColumns and sync tables.
@DataClassName('QuickInputMemoryRow')
class QuickInputMemory extends Table {
  @override
  String get tableName => 'quick_input_memory';
  TextColumn get keyword => text()();
  TextColumn get categoryId => text().named('category_id').nullable()();
  TextColumn get accountId => text().named('account_id').nullable()();
  IntColumn get count => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  @override
  Set<Column<Object>> get primaryKey => {keyword};
}

class Budgets extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get categoryId => text().named('category_id')();
  IntColumn get amount => integer()();
  DateTimeColumn get monthStart => dateTime().named('month_start')();
}

class RecurringRules extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get type => text().customConstraint(
    "NOT NULL CHECK (type IN ('income', 'expense', 'transfer'))",
  )();
  IntColumn get amount =>
      integer().customConstraint('NOT NULL CHECK (amount >= 0)')();
  TextColumn get accountId => text().named('account_id')();
  TextColumn get toAccountId => text().named('to_account_id').nullable()();
  TextColumn get categoryId => text().named('category_id').nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get frequency => text()();
  IntColumn get interval => integer().withDefault(const Constant(1))();
  DateTimeColumn get nextOccurrenceAt =>
      dateTime().named('next_occurrence_at')();
  BoolColumn get isActive =>
      boolean().named('is_active').withDefault(const Constant(true))();
}

@DriftAccessor(tables: [Accounts])
class AccountsDao extends DatabaseAccessor<AppDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.db);

  Stream<List<Account>> watchActive() =>
      (select(accounts)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm(expression: row.name)]))
          .watch();

  Stream<int> watchActiveCount() => watchActive().map((rows) => rows.length);

  Future<void> save(AccountsCompanion value) =>
      into(accounts).insertOnConflictUpdate(value);

  Future<int> softDelete(String id, DateTime now) =>
      (update(accounts)..where((row) => row.id.equals(id))).write(
        AccountsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
}

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Stream<List<Category>> watchActive() =>
      (select(categories)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm(expression: row.name)]))
          .watch();

  Stream<int> watchActiveCount() => watchActive().map((rows) => rows.length);

  Future<void> save(CategoriesCompanion value) =>
      into(categories).insertOnConflictUpdate(value);

  Future<int> softDelete(String id, DateTime now) =>
      (update(categories)..where((row) => row.id.equals(id))).write(
        CategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
}

@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  Stream<List<Transaction>> watchActive() =>
      (select(transactions)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([
              (row) => OrderingTerm(
                expression: row.occurredAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch();

  Stream<List<Transaction>> watchForPeriod(DateTime start, DateTime end) =>
      (select(transactions)
            ..where(
              (row) =>
                  row.deletedAt.isNull() &
                  row.occurredAt.isBiggerOrEqualValue(start) &
                  row.occurredAt.isSmallerThanValue(end),
            )
            ..orderBy([
              (row) => OrderingTerm(
                expression: row.occurredAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch();

  Stream<int> watchActiveCount() => watchActive().map((rows) => rows.length);

  Future<void> save(TransactionsCompanion value) =>
      into(transactions).insertOnConflictUpdate(value);

  Future<int> softDelete(String id, DateTime now) =>
      (update(transactions)..where((row) => row.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );

  Future<int> restore(String id, DateTime now) =>
      (update(transactions)..where((row) => row.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
}

@DriftAccessor(tables: [Budgets])
class BudgetsDao extends DatabaseAccessor<AppDatabase> with _$BudgetsDaoMixin {
  BudgetsDao(super.db);

  Stream<List<Budget>> watchActive() =>
      (select(budgets)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([
              (row) => OrderingTerm(
                expression: row.monthStart,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch();

  Stream<int> watchActiveCount() => watchActive().map((rows) => rows.length);

  Future<void> save(BudgetsCompanion value) =>
      into(budgets).insertOnConflictUpdate(value);

  Future<int> softDelete(String id, DateTime now) =>
      (update(budgets)..where((row) => row.id.equals(id))).write(
        BudgetsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
}

@DriftAccessor(tables: [RecurringRules])
class RecurringRulesDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringRulesDaoMixin {
  RecurringRulesDao(super.db);

  Stream<List<RecurringRule>> watchActive() =>
      (select(recurringRules)
            ..where((row) => row.deletedAt.isNull() & row.isActive.equals(true))
            ..orderBy([
              (row) => OrderingTerm(expression: row.nextOccurrenceAt),
            ]))
          .watch();

  Stream<int> watchActiveCount() => watchActive().map((rows) => rows.length);

  Future<void> save(RecurringRulesCompanion value) =>
      into(recurringRules).insertOnConflictUpdate(value);

  Future<int> softDelete(String id, DateTime now) =>
      (update(recurringRules)..where((row) => row.id.equals(id))).write(
        RecurringRulesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
}

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Transactions,
    Budgets,
    RecurringRules,
    QuickInputMemory,
  ],
  daos: [
    AccountsDao,
    CategoriesDao,
    TransactionsDao,
    BudgetsDao,
    RecurringRulesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    // Keep major 2.0 data in its own OS application-support database.
    : super(executor ?? driftDatabase(name: 'ledgy_2_0'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createParserFailures();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(transactions, transactions.recipientName);
        await migrator.addColumn(transactions, transactions.recipientAccount);
      }
      if (from < 3) {
        await migrator.createTable(quickInputMemory);
      }
      if (from < 4) await _createParserFailures();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement(
        'CREATE TABLE IF NOT EXISTS ledgy_local_state '
        '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await _installSyncMetadata();
      if (details.wasCreated) {
        await seedDefaults();
      }
      await normalizeLegacyCategories();
    },
  );

  // Text-only diagnostic data, with no ledger IDs, timestamps or sync metadata.
  Future<void> _createParserFailures() => customStatement(
    'CREATE TABLE IF NOT EXISTS parser_failures (text TEXT NOT NULL PRIMARY KEY)',
  );

  // Separate, local-only metadata keeps server microseconds intact even though
  // Drift stores ledger DateTimes as SQLite seconds. Revisions protect edits
  // made while an upload is in flight, including writes from Workmanager.
  Future<void> _installSyncMetadata() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS ledgy_sync_rows ('
      'table_name TEXT NOT NULL, row_id TEXT NOT NULL, '
      'revision INTEGER NOT NULL DEFAULT 0, server_updated_at TEXT, '
      'PRIMARY KEY(table_name, row_id))',
    );
    for (final table in [
      'accounts',
      'categories',
      'transactions',
      'budgets',
      'recurring_rules',
    ]) {
      await customStatement(
        "INSERT OR IGNORE INTO ledgy_sync_rows(table_name,row_id) "
        "SELECT '$table',id FROM $table",
      );
      for (final event in ['INSERT', 'UPDATE']) {
        await customStatement(
          'CREATE TRIGGER IF NOT EXISTS ledgy_sync_${table}_${event.toLowerCase()} '
          'AFTER $event ON $table WHEN NEW.is_dirty = 1 BEGIN '
          'INSERT INTO ledgy_sync_rows(table_name,row_id,revision) '
          "VALUES ('$table',NEW.id,1) ON CONFLICT(table_name,row_id) "
          'DO UPDATE SET revision=revision+1; END',
        );
      }
    }
  }

  /// Renames the older food categories without losing links from historical
  /// transactions, budgets, or recurring rules. Duplicate legacy rows are
  /// merged into one active category and then soft-deleted.
  Future<void> normalizeLegacyCategories() async {
    final now = DateTime.now().toUtc();
    final activeCategories = await (select(
      categories,
    )..where((row) => row.deletedAt.isNull())).get();
    final orderedCategories = [...activeCategories]
      ..sort((left, right) {
        final leftIsCurrent = left.name == _normalizedCategoryName(left.name);
        final rightIsCurrent =
            right.name == _normalizedCategoryName(right.name);
        final preference = (leftIsCurrent ? 0 : 1).compareTo(
          rightIsCurrent ? 0 : 1,
        );
        return preference != 0 ? preference : left.id.compareTo(right.id);
      });
    final keeperByNameAndKind = <String, String>{};

    for (final category in orderedCategories) {
      final normalizedName = _normalizedCategoryName(category.name);
      final key = '${category.kind}\u0000$normalizedName';
      final keeperId = keeperByNameAndKind[key];

      if (keeperId == null) {
        keeperByNameAndKind[key] = category.id;
        if (category.name != normalizedName) {
          await (update(
            categories,
          )..where((row) => row.id.equals(category.id))).write(
            CategoriesCompanion(
              name: Value(normalizedName),
              updatedAt: Value(now),
              isDirty: const Value(true),
            ),
          );
        }
        continue;
      }

      await (update(
        transactions,
      )..where((row) => row.categoryId.equals(category.id))).write(
        TransactionsCompanion(
          categoryId: Value(keeperId),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
      await (update(
        budgets,
      )..where((row) => row.categoryId.equals(category.id))).write(
        BudgetsCompanion(
          categoryId: Value(keeperId),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
      await (update(
        recurringRules,
      )..where((row) => row.categoryId.equals(category.id))).write(
        RecurringRulesCompanion(
          categoryId: Value(keeperId),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
      await (update(
        categories,
      )..where((row) => row.id.equals(category.id))).write(
        CategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
    }
  }

  Future<void> seedDefaults() async {
    final now = DateTime.now().toUtc();
    final uuid = const Uuid();
    final seededAccounts = await (select(
      accounts,
    )..where((row) => row.deletedAt.isNull())).get();
    if (seededAccounts.isEmpty) {
      await into(accounts).insert(
        AccountsCompanion.insert(
          id: uuid.v4(),
          name: 'Tunai',
          createdAt: now,
          updatedAt: now,
          isDirty: const Value(false),
        ),
      );
    }

    const categoriesToSeed = <({String name, String kind})>[
      (name: 'Makan & Minum', kind: 'expense'),
      (name: 'Transport', kind: 'expense'),
      (name: 'Belanja', kind: 'expense'),
      (name: 'Tagihan', kind: 'expense'),
      (name: 'Hiburan', kind: 'expense'),
      (name: 'Kesehatan', kind: 'expense'),
      (name: 'Gaji', kind: 'income'),
      (name: 'Lainnya', kind: 'expense'),
    ];
    for (final category in categoriesToSeed) {
      final existingCategories =
          await (select(categories)..where(
                (row) =>
                    row.name.equals(category.name) & row.deletedAt.isNull(),
              ))
              .get();
      if (existingCategories.isEmpty) {
        await into(categories).insert(
          CategoriesCompanion.insert(
            id: uuid.v4(),
            name: category.name,
            kind: Value(category.kind),
            createdAt: now,
            updatedAt: now,
            isDirty: const Value(false),
          ),
        );
      }
    }
  }
}

String _normalizedCategoryName(String name) {
  final parts = name.split('•').map((part) => part.trim()).toList();
  if (parts.isEmpty) return name;
  final parent = parts.first.toLowerCase();
  if (parent == 'makanan' || parent == 'makanan & minuman') {
    parts[0] = 'Makan & Minum';
  }
  if (parts.length > 1 && parts.last.toLowerCase() == 'cafe /warkop') {
    parts[parts.length - 1] = 'Cafe / Warkop';
  }
  return parts.join(' • ');
}
