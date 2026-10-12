import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/quick_input/domain/parser/transaction_parser.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';
import 'package:ledgy/features/quick_input/domain/voice_normalizer.dart';

void main() {
  final ctx = ParserContext(
    clock: FixedClock(DateTime(2026, 10, 8, 10)),
    lastAccountId: 'tunai',
    accounts: [
      for (final name in ['Tunai', 'BCA', 'GoPay', 'DANA'])
        ParserAccount(id: name.toLowerCase(), name: name),
    ],
    categories: const [
      ParserCategory(
        id: 'food',
        name: 'Makanan',
        type: TransactionType.expense,
      ),
      ParserCategory(
        id: 'transport',
        name: 'Transport',
        type: TransactionType.expense,
      ),
      ParserCategory(id: 'salary', name: 'Gaji', type: TransactionType.income),
    ],
  );
  for (final row in [
    (
      'makan siang tiga puluh lima ribu rupiah pakai go pay',
      35000,
      'gopay',
      'food',
      TransactionType.expense,
      'makan siang',
    ),
    (
      'bensin lima puluh ribu',
      50000,
      'tunai',
      'transport',
      TransactionType.expense,
      'bensin',
    ),
    (
      'gaji delapan juta masuk ke b c a',
      8000000,
      'bca',
      'salary',
      TransactionType.income,
      'gaji masuk',
    ),
  ]) {
    test('hasil suara: ${row.$1}', () {
      final draft = parse(const VoiceNormalizer().normalize(row.$1), ctx);
      expect(draft.amount, row.$2);
      expect(draft.accountId, row.$3);
      expect(draft.categoryId, row.$4);
      expect(draft.type, row.$5);
      expect(draft.note, row.$6);
      expect(draft.occurredAt, DateTime(2026, 10, 8, 10).toUtc());
    });
  }
  test(
    'variasi kapital/spasi dan gopay tidak mengubah angka kata atau rupiah',
    () {
      expect(
        const VoiceNormalizer().normalize(
          '  GAJI  delapan juta  masuk ke B C A ',
        ),
        'gaji delapan juta masuk ke bca',
      );
      expect(
        const VoiceNormalizer().normalize(
          'go pay gopay gojek rupiah tiga puluh',
        ),
        'gopay gopay gojek rupiah tiga puluh',
      );
    },
  );
  test('ucapan tanpa jumlah tetap draf kosong, bukan simpan otomatis', () {
    final draft = parse(
      const VoiceNormalizer().normalize('makan pakai go pay'),
      ctx,
    );
    expect(draft.amount, isNull);
    expect(
      draft.warnings.any((warning) => warning.code == 'NO_AMOUNT'),
      isTrue,
    );
  });
}
