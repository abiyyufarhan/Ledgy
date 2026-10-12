import '../transaction_draft.dart';
import 'draft_parser.dart';
import 'parser_context.dart';
import 'parser_inspection.dart';
import 'transaction_parser.dart' as rules;

/// Async adapter for the existing pure Dart parser, retaining every draft.
final class RuleBasedParser implements DraftParser {
  const RuleBasedParser();

  @override
  Future<List<TransactionDraft>> parse(String text, ParserContext ctx) async =>
      rules.parseMany(text, ctx);

  Future<List<TransactionDraft>> inspect(
    String text,
    ParserContext ctx,
    ParserObserver observer,
  ) async => rules.parseMany(text, ctx, observer: observer);
}
