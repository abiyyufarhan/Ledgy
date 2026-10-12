import 'parser/parser_context.dart';
import 'transaction_draft.dart';

abstract interface class ParserFailureRepository {
  Future<bool> enabled();
  Future<void> setEnabled(bool value);
  Future<void> record(
    String text,
    List<TransactionDraft> drafts,
    ParserContext context,
  );
  Future<List<String>> readAll();
  Future<void> clear();
}
