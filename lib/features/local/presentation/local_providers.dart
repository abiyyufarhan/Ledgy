import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/local_finance_repository.dart';

final localFinanceProvider = Provider(
  (ref) => LocalFinanceRepository(ref.watch(databaseProvider)),
);
final recurringRulesProvider = StreamProvider(
  (ref) => ref.watch(localFinanceProvider).watchRules(),
);
final financeSnapshotProvider = FutureProvider((ref) {
  ref.watch(accountsProvider);
  ref.watch(categoriesProvider);
  ref.watch(transactionsProvider);
  ref.watch(budgetsProvider);
  ref.watch(recurringRulesProvider);
  return ref.watch(localFinanceProvider).snapshot();
});
