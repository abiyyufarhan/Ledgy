import '../transaction_draft.dart';

final class ParserStep {
  const ParserStep(this.name, this.detail);
  final String name;
  final String detail;
}

typedef ParserObserver = void Function(ParserStep step);

final class ParserInspection {
  ParserInspection({
    required List<TransactionDraft> drafts,
    required List<ParserStep> steps,
    required this.elapsed,
  }) : drafts = List.unmodifiable(drafts),
       steps = List.unmodifiable(steps);
  final List<TransactionDraft> drafts;
  final List<ParserStep> steps;
  final Duration elapsed;
}
