import 'package:ledgy/features/quick_input/domain/parser_failure_repository.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_context.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

class FakeParserFailures implements ParserFailureRepository {
  bool active = false;
  int records = 0;
  final rows = <String>[];
  @override
  Future<bool> enabled() async => active;
  @override
  Future<void> setEnabled(bool value) async {
    active = value;
  }

  @override
  Future<void> record(
    String text,
    List<TransactionDraft> drafts,
    ParserContext context,
  ) async {
    records++;
    if (active) rows.add(text);
  }

  @override
  Future<List<String>> readAll() async => rows;
  @override
  Future<void> clear() async {
    rows.clear();
  }
}
