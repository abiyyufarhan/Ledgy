import '../transaction_draft.dart';
import 'parser_context.dart';

/// Parser boundary shared by local rules and any future optional fallback.
abstract interface class DraftParser {
  Future<List<TransactionDraft>> parse(String text, ParserContext ctx);
}

/// Extension point only: Tier 0 has no fallback implementation or transport.
abstract interface class FallbackParser implements DraftParser {}
