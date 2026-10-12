import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/accounts/data/repositories/accounts_repository_impl.dart';
import '../../features/budgets/data/repositories/budgets_repository_impl.dart';
import '../../features/categories/data/repositories/categories_repository_impl.dart';
import '../../features/transactions/data/repositories/transactions_repository_impl.dart';
import '../database/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => AccountsRepository(ref.watch(databaseProvider).accountsDao),
);
final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => CategoriesRepository(ref.watch(databaseProvider).categoriesDao),
);
final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => TransactionsRepository(ref.watch(databaseProvider).transactionsDao),
);
final budgetsRepositoryProvider = Provider<BudgetsRepository>(
  (ref) => BudgetsRepository(ref.watch(databaseProvider).budgetsDao),
);

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).watchAll(),
);
final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoriesRepositoryProvider).watchAll(),
);
final transactionsProvider = StreamProvider<List<Transaction>>(
  (ref) => ref.watch(transactionsRepositoryProvider).watchAll(),
);
final budgetsProvider = StreamProvider<List<Budget>>(
  (ref) => ref.watch(budgetsRepositoryProvider).watchAll(),
);

final accountActionsProvider = Provider<AccountActions>(
  (ref) => AccountActions(ref.watch(accountsRepositoryProvider)),
);
final categoryActionsProvider = Provider<CategoryActions>(
  (ref) => CategoryActions(ref.watch(categoriesRepositoryProvider)),
);
final transactionActionsProvider = Provider<TransactionActions>(
  (ref) => TransactionActions(ref.watch(transactionsRepositoryProvider)),
);

class AccountActions {
  AccountActions(this._repository);
  final AccountsRepository _repository;

  Future<void> save({
    String? id,
    required String name,
    required int initialBalance,
  }) {
    final now = DateTime.now().toUtc();
    return _repository.save(
      AccountsCompanion.insert(
        id: id ?? const Uuid().v4(),
        name: name.trim(),
        initialBalance: Value(initialBalance),
        createdAt: now,
        updatedAt: now,
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> archive(String id) async =>
      _repository.softDelete(id, DateTime.now());
}

class CategoryActions {
  CategoryActions(this._repository);
  final CategoriesRepository _repository;

  Future<void> save({String? id, required String name, required String kind}) {
    final now = DateTime.now().toUtc();
    return _repository.save(
      CategoriesCompanion.insert(
        id: id ?? const Uuid().v4(),
        name: name.trim(),
        kind: Value(kind),
        createdAt: now,
        updatedAt: now,
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> archive(String id) async =>
      _repository.softDelete(id, DateTime.now());
}

class TransactionActions {
  TransactionActions(this._repository);
  final TransactionsRepository _repository;

  Future<void> save({
    String? id,
    required String type,
    required int amount,
    required String accountId,
    String? toAccountId,
    String? recipientName,
    String? recipientAccount,
    String? categoryId,
    String? note,
    required DateTime occurredAt,
  }) {
    final now = DateTime.now().toUtc();
    return _repository.save(
      TransactionsCompanion.insert(
        id: id ?? const Uuid().v4(),
        type: type,
        amount: amount,
        accountId: accountId,
        toAccountId: Value(toAccountId),
        recipientName: Value(recipientName),
        recipientAccount: Value(recipientAccount),
        categoryId: Value(categoryId),
        note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
        occurredAt: occurredAt.toUtc(),
        createdAt: now,
        updatedAt: now,
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> archive(String id) async =>
      _repository.softDelete(id, DateTime.now());
  Future<void> restore(String id) async =>
      _repository.restore(id, DateTime.now());
}
