import '../transaction_draft.dart';
import 'draft_parser.dart';
import 'parser_context.dart';
import 'rule_based_parser.dart';
import 'parser_inspection.dart';

/// Tier 0 runs local rules only. No network client is constructed here.
final class ParserPipeline implements DraftParser {
  const ParserPipeline({
    DraftParser ruleBasedParser = const RuleBasedParser(),
    this.fallbackParser,
    this.aiFallbackEnabled = false,
  }) : _rules = ruleBasedParser;

  final DraftParser _rules;
  final FallbackParser? fallbackParser;
  final bool aiFallbackEnabled;

  static bool needsManualCompletion(TransactionDraft draft) =>
      draft.confidence < .6 || draft.amount == null;

  Future<ParserInspection> inspect(String text, ParserContext ctx) async {
    final steps = <ParserStep>[];
    final timer = Stopwatch()..start();
    final rules = _rules;
    final local = rules is RuleBasedParser
        ? await rules.inspect(text, ctx, steps.add)
        : await rules.parse(text, ctx);
    final drafts = await _finish(text, ctx, local);
    timer.stop();
    steps.add(
      ParserStep(
        'Pipeline',
        'Fallback AI ${aiFallbackEnabled && fallbackParser != null ? "diizinkan" : "nonaktif"}; ${drafts.length} draf',
      ),
    );
    return ParserInspection(
      drafts: drafts,
      steps: steps,
      elapsed: timer.elapsed,
    );
  }

  @override
  Future<List<TransactionDraft>> parse(String text, ParserContext ctx) async {
    return _finish(text, ctx, await _rules.parse(text, ctx));
  }

  Future<List<TransactionDraft>> _finish(
    String text,
    ParserContext ctx,
    List<TransactionDraft> local,
  ) async {
    final drafts = List<TransactionDraft>.unmodifiable(local);
    final fallback = fallbackParser;
    // Check the flag before ever invoking the optional extension point.
    if (!aiFallbackEnabled ||
        fallback == null ||
        !drafts.any(needsManualCompletion)) {
      return drafts;
    }
    // A batch is parsed once as a whole; do not duplicate its transactions.
    // Optional future failures leave the local drafts available for editing.
    try {
      final result = await fallback.parse(text, ctx);
      return result.isEmpty
          ? drafts
          : List<TransactionDraft>.unmodifiable(result);
    } catch (_) {
      return drafts;
    }
  }
}
