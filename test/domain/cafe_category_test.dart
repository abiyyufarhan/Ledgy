import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_context.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_pipeline.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

ParserContext _context({
  bool cafe = true,
  List<KeywordMemory> memory = const [],
}) => ParserContext(
  clock: FixedClock(DateTime.utc(2026, 10, 8, 10)),
  accounts: [ParserAccount(id: 'cash', name: 'Tunai')],
  lastAccountId: 'cash',
  categories: [
    const ParserCategory(
      id: 'food',
      name: 'Makan & Minum',
      type: TransactionType.expense,
    ),
    // Deliberately placed before Cafe: it must not inherit parent's kopi.
    const ParserCategory(
      id: 'restaurant',
      name: 'Makan & Minum • Restoran',
      type: TransactionType.expense,
    ),
    if (cafe)
      const ParserCategory(
        id: 'cafe',
        name: 'Makan & Minum • Cafe / Warkop',
        type: TransactionType.expense,
      ),
    const ParserCategory(
      id: 'fun',
      name: 'Hiburan',
      type: TransactionType.expense,
    ),
    const ParserCategory(
      id: 'income-cafe',
      name: 'Cafe / Warkop',
      type: TransactionType.income,
    ),
  ],
  memory: memory,
);

void main() {
  for (final text in [
    'minum kopi 35rb pakai Tunai',
    'ngopi 20rb via Tunai',
    'bayar warkop 15rb via Tunai',
    'beli coffee 40rb via Tunai',
    'makan di kafe 50rb via Tunai',
    'minum kopi',
  ]) {
    test('$text automatically chooses Cafe / Warkop', () async {
      final draft = (await const ParserPipeline().parse(
        text,
        _context(),
      )).single;
      expect(draft.categoryId, 'cafe');
      expect(draft.type, TransactionType.expense);
      expect(
        draft.warnings.where((w) => w.code == 'MULTIPLE_CATEGORIES'),
        isEmpty,
      );
    });
  }
  test('without Cafe, coffee falls back to parent, never Restoran', () async {
    final draft = (await const ParserPipeline().parse(
      'minum kopi 20rb',
      _context(cafe: false),
    )).single;
    expect(draft.categoryId, 'food');
  });
  test(
    'ordinary meals stay in parent and keyword boundaries are respected',
    () async {
      final pipeline = const ParserPipeline();
      expect(
        (await pipeline.parse('makan nasi 20rb', _context())).single.categoryId,
        'food',
      );
      expect(
        (await pipeline.parse('fotokopi 20rb', _context())).single.categoryId,
        isNull,
      );
    },
  );
  test('learned user category still overrides the Cafe rule', () async {
    final ctx = _context(
      memory: [
        KeywordMemory(
          keyword: 'kopi',
          categoryId: 'fun',
          count: 3,
          updatedAt: DateTime.utc(2026, 10, 8),
        ),
      ],
    );
    expect(
      (await const ParserPipeline().parse(
        'minum kopi 20rb',
        ctx,
      )).single.categoryId,
      'fun',
    );
  });
}
