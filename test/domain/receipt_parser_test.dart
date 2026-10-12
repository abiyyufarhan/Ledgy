import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/quick_input/domain/receipt/ocr_line.dart';
import 'package:ledgy/features/quick_input/domain/receipt/receipt_parser.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_context.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

ParserContext context({List<KeywordMemory> memory = const []}) => ParserContext(
  clock: FixedClock(DateTime.utc(2026, 10, 8, 10)),
  accounts: [
    for (final name in ['Tunai', 'BCA', 'GoPay', 'DANA'])
      ParserAccount(id: name, name: name),
  ],
  lastAccountId: 'BCA',
  memory: memory,
  categories: [
    for (final name in [
      'Makanan',
      'Transport',
      'Belanja',
      'Kesehatan',
      'Tagihan',
      'Cafe / Warkop',
    ])
      ParserCategory(id: name, name: name, type: TransactionType.expense),
  ],
);
List<OcrLine> rows(List<String> text) => [
  for (var i = 0; i < text.length; i++)
    OcrLine(
      text: text[i],
      left: 0,
      top: i * 30,
      right: 600,
      bottom: i * 30 + 20,
    ),
];
void main() {
  const parser = ReceiptParser();
  const cases = {
    'minimarket': (30000, 2, 'Belanja', 'Tunai'),
    'restoran': (52200, 2, 'Makanan', 'BCA'),
    'spbu': (50000, 1, 'Transport', 'BCA'),
    'apotek': (40000, 2, 'Kesehatan', 'DANA'),
    'diskon_panjang': (120000, 6, 'Belanja', 'GoPay'),
    'total_terpotong': (35000, 2, 'Makanan', 'Tunai'),
    'buram': (35000, 1, 'Cafe / Warkop', 'Tunai'),
    'miring': (30000, 1, 'Transport', 'Tunai'),
  };
  for (final entry in cases.entries) {
    test('fixture sintetis ${entry.key}', () {
      final json = jsonDecode(
        File('test/fixtures/receipts/${entry.key}.json').readAsStringSync(),
      ) as List;
      final lines = json
          .map((l) => OcrLine.fromJson(Map<String, dynamic>.from(l as Map)))
          .toList();
      final draft = parser.parse(lines, context());
      expect(draft.source, DraftSource.receipt);
      expect(draft.amount, entry.value.$1);
      expect(draft.items.length, entry.value.$2);
      expect(draft.categoryId, entry.value.$3);
      expect(draft.accountId, entry.value.$4);
      expect(draft.occurredAt!.isUtc, isTrue);
      expect(draft.occurredAt!.day, 8);
      expect(draft.warnings.where((w) => w.code == 'TOTAL_MISMATCH'), isEmpty);
      expect(draft.note, endsWith('- ${entry.value.$2} item'));
      if (entry.key == 'total_terpotong') {
        expect(draft.warnings.map((w) => w.code), contains('TOTAL_FALLBACK'));
      }
    });
  }
  test(
    'rightmost price, exclusions, total on next row, quantity and cents',
    () {
      final draft = parser.parse(
        rows([
          'RESTO',
          '08/10/2026 12:34',
          'NASI 2 x 15.000 30.000,00',
          'SUBTOTAL 30.000',
          'TOTAL ITEM 2',
          'TOTAL QTY 2',
          'TOTAL',
          'Rp30.000,00',
          'TUNAI 50.000',
          'CHANGE 20.000',
        ]),
        context(),
      );
      expect(draft.amount, 30000);
      expect(draft.items.single.amount, 30000);
      expect(draft.occurredAt, DateTime.utc(2026, 10, 8, 12, 34));
    },
  );
  test('cross validation warning above 1%, exact 1% accepted', () {
    TransactionDraft draft(int total) =>
        parser.parse(rows(['RESTO', 'NASI 10.000', 'TOTAL $total']), context());
    expect(
      draft(12000).warnings.map((w) => w.code),
      contains('TOTAL_MISMATCH'),
    );
    expect(
      draft(10100).warnings.map((w) => w.code),
      isNot(contains('TOTAL_MISMATCH')),
    );
    expect(draft(12000).confidence, lessThan(draft(10000).confidence));
  });
  test('default and invalid dates warn, empty OCR stays incomplete', () {
    final draft = parser.parse(
      rows(['PLN', '31/02/2026', 'TAGIHAN Rp35.000']),
      context(),
    );
    expect(draft.occurredAt, DateTime.utc(2026, 10, 8, 10));
    expect(draft.categoryId, 'Tagihan');
    expect(draft.warnings.map((w) => w.code), contains('DEFAULT_DATE'));
    expect(parser.parse([], context()).amount, isNull);
  });
  test('numeric corrections do not change item or merchant words', () {
    final draft = parser.parse(
      rows(['BAKSO SOLO', 'BAKSO ISI 1 1O.OOO', 'TOTAL Rp1O.OOO']),
      context(),
    );
    expect(draft.amount, 10000);
    expect(draft.items.single.name, 'BAKSO ISI 1');
    expect(draft.note, startsWith('BAKSO SOLO'));
    expect(draft.rawText, contains('1O.OOO'));
  });
  test('date-only text is not an item; OCR date and time are repaired', () {
    final draft = parser.parse(
      rows(['RESTO', 'O8/1O/2O26 1O:3O', 'NASI RpI5.OOO', 'TOTAL RpI5.OOO']),
      context(),
    );
    expect(draft.items.length, 1);
    expect(draft.amount, 15000);
    expect(draft.occurredAt, DateTime.utc(2026, 10, 8, 10, 30));
    expect(draft.warnings.map((w) => w.code), contains('DATE_OCR_CORRECTED'));
    final dateOnly = parser.parse(
      rows(['RESTO', '8 Okt 2026', 'NASI 15000', 'TOTAL 15000']),
      context(),
    );
    expect(dateOnly.items.length, 1);
  });
  test('negative discounts and total followed by currency text', () {
    final draft = parser.parse(
      rows([
        'RESTO',
        'NASI 10.000',
        'DISKON -1.000',
        'TOTAL',
        '9.000 IDR',
        'TUNAI',
      ]),
      context(),
    );
    expect(draft.amount, 9000);
    expect(
      draft.warnings.map((w) => w.code),
      isNot(contains('TOTAL_MISMATCH')),
    );
  });
  test('user memory outranks store dictionary, inactive IDs ignored', () {
    final draft = parser.parse(
      rows(['INDOMARET', 'TOTAL 35.000']),
      context(
        memory: [
          KeywordMemory(
            keyword: 'indomaret',
            categoryId: 'Makanan',
            count: 3,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    expect(draft.categoryId, 'Makanan');
  });
  test('QRIS does not guess a bank; only valid last account is used', () {
    final draft = parser.parse(
      rows(['RESTO', 'TOTAL 35.000', 'QRIS']),
      context(),
    );
    expect(draft.accountId, 'BCA');
    expect(draft.warnings.map((w) => w.code), contains('DEFAULT_ACCOUNT'));
  });
  test('geometry joins aligned fragments, keeps adjacent rows and sorts x', () {
    final merged = mergeOcrLines([
      const OcrLine(text: '35.000', left: 400, top: 8, right: 590, bottom: 28),
      const OcrLine(text: 'NASI', left: 0, top: 0, right: 200, bottom: 20),
      const OcrLine(
        text: 'TEH 10.000',
        left: 0,
        top: 35,
        right: 590,
        bottom: 55,
      ),
    ]);
    expect(merged.map((l) => l.text), ['NASI 35.000', 'TEH 10.000']);
    expect(OcrLine.fromJson(merged.first.toJson()).text, merged.first.text);
  });
}
