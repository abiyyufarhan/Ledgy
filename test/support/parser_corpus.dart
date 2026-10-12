import 'package:ledgy/features/quick_input/domain/parser/parser_context.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

ParserContext corpusContext() => ParserContext(
  clock: FixedClock(DateTime.utc(2026, 10, 8, 10)),
  accounts: [
    for (final name in ['Tunai', 'BCA', 'GoPay', 'DANA'])
      ParserAccount(id: name, name: name),
  ],
  lastAccountId: 'Tunai',
  categories: [
    for (final name in [
      'Makanan',
      'Cafe / Warkop',
      'Transport',
      'Tagihan',
      'Belanja',
      'Hiburan',
      'Kesehatan',
    ])
      ParserCategory(id: name, name: name, type: TransactionType.expense),
    for (final name in ['Gaji', 'Refund', 'Cashback'])
      ParserCategory(id: name, name: name, type: TransactionType.income),
  ],
);

/// CSV reader for fixtures: quoted commas/newlines and escaped quotes supported.
List<List<String>> readCorpusCsv(String csv) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < csv.length; i++) {
    final c = csv[i];
    if (c == '"') {
      if (quoted && i + 1 < csv.length && csv[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n' && !quoted) {
      row.add(field.toString().replaceFirst(RegExp(r'\r$'), ''));
      rows.add(row);
      row = [];
      field = StringBuffer();
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('Kutip CSV tidak ditutup');
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
