import '../../local/data/local_finance_repository.dart';
import '../domain/draft_validator.dart';
import '../domain/parser/parser_context.dart';
import '../domain/parser_failure_repository.dart';
import '../domain/transaction_draft.dart';

final class SqliteParserFailureRepository implements ParserFailureRepository {
  const SqliteParserFailureRepository(this.finance);
  final LocalFinanceRepository finance;
  @override
  Future<bool> enabled() async =>
      await finance.state('parser:record_failures') == 'true';
  @override
  Future<void> setEnabled(bool value) =>
      finance.setState('parser:record_failures', '$value');
  @override
  Future<void> record(
    String text,
    List<TransactionDraft> drafts,
    ParserContext context,
  ) async {
    if (!await enabled() || text.trim().isEmpty) return;
    if (drafts.any((draft) => draft.source != DraftSource.text)) return;
    final failed =
        drafts.isEmpty ||
        drafts.any(
          (d) =>
              d.confidence < .6 ||
              const DraftValidator()
                  .validate(d, now: context.clock.now())
                  .isNotEmpty,
        );
    if (!failed) return;
    await finance.db.transaction(() async {
      // Bound local storage. Repeated text is deduplicated; no extra data stored.
      await finance.db.customStatement(
        'INSERT OR IGNORE INTO parser_failures(text) VALUES (?)',
        [text.trim()],
      );
      await finance.db.customStatement(
        'DELETE FROM parser_failures WHERE rowid NOT IN (SELECT rowid FROM parser_failures ORDER BY rowid DESC LIMIT 500)',
      );
    });
  }

  @override
  Future<List<String>> readAll() async =>
      (await finance.db
              .customSelect(
                'SELECT text FROM parser_failures ORDER BY rowid DESC',
              )
              .get())
          .map((r) => r.read<String>('text'))
          .toList(growable: false);
  @override
  Future<void> clear() =>
      finance.db.customStatement('DELETE FROM parser_failures');
}
