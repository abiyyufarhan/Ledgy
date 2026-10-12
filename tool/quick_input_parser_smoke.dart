import 'dart:io';

import 'package:ledgy/features/quick_input/domain/parser/transaction_parser.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

void main() {
  final ctx = ParserContext(
    clock: FixedClock(DateTime.utc(2026, 10, 8, 10)),
    accounts: [ParserAccount(id: 'bca', name: 'BCA')],
    categories: [
      const ParserCategory(
        id: 'food',
        name: 'Makanan',
        type: TransactionType.expense,
      ),
    ],
  );
  final draft = parse('makan kopi 35rb via BCA kemarin', ctx);
  if (draft.amount != 35000 ||
      draft.accountId != 'bca' ||
      draft.categoryId != 'food' ||
      draft.occurredAt != DateTime.utc(2026, 10, 7, 10)) {
    throw StateError('Parser smoke test failed');
  }
  stdout.writeln(
    'PASS: parser runs in the standalone Dart VM without Flutter.',
  );
}
