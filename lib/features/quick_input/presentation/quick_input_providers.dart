import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/quick_input_actions.dart';
import '../data/quick_input_categories.dart';
import '../data/sqlite_quick_input_memory_repository.dart';
import '../data/speech_voice_backend.dart';
import '../domain/voice_input_backend.dart';
import '../domain/parser/parser_context.dart';
import '../domain/parser/parser_pipeline.dart';
import '../domain/quick_input_memory_repository.dart';
import '../domain/transaction_draft.dart';
import 'receipt_providers.dart';
import '../../local/presentation/local_providers.dart';
import '../data/sqlite_parser_failure_repository.dart';
import '../domain/parser_failure_repository.dart';

final parserFailureRepositoryProvider = Provider<ParserFailureRepository>(
  (ref) => SqliteParserFailureRepository(ref.watch(localFinanceProvider)),
);
final parserFailureRecordingProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(parserFailureRepositoryProvider).enabled(),
);
final parserFailuresProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(parserFailureRepositoryProvider).readAll(),
);

final parserClockProvider = Provider<Clock>((ref) => const SystemClock());
// Tier 0 deliberately supplies neither a fallback nor an enabled AI flag.
final parserPipelineProvider = Provider<ParserPipeline>(
  (ref) => const ParserPipeline(),
);
final voiceInputBackendProvider = Provider<VoiceInputBackend>(
  (ref) => SpeechVoiceBackend(),
);
final quickInputMemoryRepositoryProvider = Provider<QuickInputMemoryRepository>(
  (ref) => SqliteQuickInputMemoryRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(parserClockProvider),
  ),
);
final quickInputMemoryProvider = StreamProvider<List<KeywordMemory>>(
  (ref) => ref.watch(quickInputMemoryRepositoryProvider).watchAll(),
);
final quickInputCategoriesProvider = Provider<QuickInputCategories>(
  (ref) => QuickInputCategories(ref.watch(categoriesRepositoryProvider)),
);
final quickInputCategoryChoicesProvider = Provider((ref) {
  final catalog = ref.watch(quickInputCategoriesProvider);
  return ref.watch(categoriesProvider).whenData(catalog.preview);
});
final quickInputActionsProvider = Provider<QuickInputActions>(
  (ref) => QuickInputActions(
    ref.watch(databaseProvider),
    ref.watch(transactionActionsProvider),
    ref.watch(quickInputMemoryRepositoryProvider),
    categories: ref.watch(quickInputCategoriesProvider),
    receipts: ref.watch(receiptStorageProvider),
  ),
);

final parserContextProvider = FutureProvider<ParserContext>((ref) async {
  final clock = ref.watch(parserClockProvider);
  final accounts = await ref.watch(accountsProvider.future);
  final categories = ref
      .watch(quickInputCategoriesProvider)
      .preview(await ref.watch(categoriesProvider.future));
  final memory = await ref.watch(quickInputMemoryProvider.future);
  // Recompute the last-used hint when transaction data changes.
  await ref.watch(transactionsProvider.future);
  final last = await ref
      .watch(quickInputMemoryRepositoryProvider)
      .lastAccountId();
  return ParserContext(
    clock: clock,
    accounts: [
      for (final account in accounts)
        ParserAccount(id: account.id, name: account.name),
    ],
    categories: [
      for (final category in categories)
        ParserCategory(
          id: category.id,
          name: category.name,
          type: category.kind == 'income'
              ? TransactionType.income
              : TransactionType.expense,
        ),
    ],
    memory: memory,
    lastAccountId: last,
  );
});
