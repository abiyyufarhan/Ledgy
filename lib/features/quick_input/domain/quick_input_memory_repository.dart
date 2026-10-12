import 'parser/parser_context.dart';
import 'transaction_draft.dart';

abstract interface class QuickInputMemoryRepository {
  Stream<List<KeywordMemory>> watchAll();
  Future<List<KeywordMemory>> readAll();
  Future<String?> lastAccountId();
  Future<void> learn(TransactionDraft original, TransactionDraft corrected);
}
