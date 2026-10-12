import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/quick_input/domain/parser/amount_parser.dart';
import 'package:ledgy/features/quick_input/domain/parser/category_matcher.dart';
import 'package:ledgy/features/quick_input/domain/parser/normalizer.dart';
import 'package:ledgy/features/quick_input/domain/parser/transaction_parser.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

final _now = DateTime(2026, 10, 8, 10);
ParserContext context({
  List<KeywordMemory> memory = const [],
  String? lastAccountId = 'cash',
}) => ParserContext(
  clock: FixedClock(_now),
  accounts: [
    ParserAccount(id: 'cash', name: 'Tunai', aliases: ['cash']),
    ParserAccount(id: 'bca', name: 'BCA', aliases: ['bank bca']),
    ParserAccount(id: 'gopay', name: 'GoPay', aliases: ['go pay']),
    ParserAccount(id: 'dana', name: 'DANA'),
  ],
  categories: [
    for (final name in [
      'Makanan',
      'Transport',
      'Tagihan',
      'Belanja',
      'Hiburan',
      'Kesehatan',
    ])
      ParserCategory(
        id: name.toLowerCase(),
        name: name,
        type: TransactionType.expense,
      ),
    for (final name in ['Gaji', 'Refund', 'Cashback'])
      ParserCategory(
        id: name.toLowerCase(),
        name: name,
        type: TransactionType.income,
      ),
  ],
  memory: memory,
  lastAccountId: lastAccountId,
);

List<String> codes(TransactionDraft draft) =>
    draft.warnings.map((w) => w.code).toList();

class _AdvancingClock implements Clock {
  int calls = 0;
  @override
  DateTime now() => _now.add(Duration(days: calls++));
}

void main() {
  test(
    'normalisasi huruf, spasi, rupiah dan variasi GoPay tanpa mengubah gojek',
    () {
      expect(
        const Normalizer().normalize(
          '  BAYAR   Rp. 35.000  via GO PAY dan gojek rupiah rp ',
        ),
        'bayar ¤ 35.000 via gopay dan gojek ¤ ¤',
      );
      expect(const Normalizer().normalize('rp35000'), '¤ 35000');
    },
  );

  final amounts = <String, int>{
    '35rb': 35000,
    '35 ribu': 35000,
    '35k': 35000,
    '2jt': 2000000,
    '2 juta': 2000000,
    'setengah juta': 500000,
    'sejuta': 1000000,
    'seribu': 1000,
    '1 juta 200 ribu': 1200000,
    '2,5jt': 2500000,
    '1.5 juta': 1500000,
    'dua puluh lima ribu': 25000,
    'seratus ribu': 100000,
    'tiga ratus lima puluh ribu': 350000,
    'lima belas ribu rupiah': 15000,
    '35.000': 35000,
    '35,000': 35000,
    '1,5 juta': 1500000,
    'rp 500': 500,
    '500 rupiah': 500,
    'rp.35.000': 35000,
    'rupiah 1500': 1500,
    '1000': 1000,
    '0,5juta': 500000,
    'sebelas ribu': 11000,
    'sembilan puluh sembilan ribu': 99000,
    'dua ratus sebelas ribu': 211000,
    'satu juta dua ratus lima puluh ribu': 1250000,
    '1.000.000': 1000000,
    '1,000,000': 1000000,
    '9007199254740993': 9007199254740993,
  };
  for (final entry in amounts.entries) {
    test('jumlah ${entry.key} = ${entry.value}', () {
      expect(
        parse('bayar ${entry.key} pakai BCA', context()).amount,
        entry.value,
      );
    });
  }
  test(
    'jumlah sangat besar tetap persis sebagai integer, overflow ditolak',
    () {
      expect(
        parse('bayar 9223372036854775807 via BCA', context()).amount,
        9223372036854775807,
      );
      final overflow = parse(
        'bayar 9223372036854775808 rupiah via BCA',
        context(),
      );
      expect(overflow.amount, isNull);
      expect(codes(overflow), contains('AMOUNT_OVERFLOW'));
    },
  );
  test('pecahan rupiah tidak dibulatkan', () {
    final draft = parse('beli 0,0005 ribu via BCA', context());
    expect(draft.amount, isNull);
    expect(codes(draft), contains('FRACTIONAL_RUPIAH'));
  });
  for (final text in [
    'beli 2 porsi',
    'tanggal 5',
    'beli 999',
    'beli kopi',
    '',
    'tahun 2026',
    'nomor rekening 123456',
  ]) {
    test('bukan jumlah: $text', () {
      final draft = parse(text, context());
      expect(draft.amount, isNull);
      expect(codes(draft), contains('NO_AMOUNT'));
    });
  }
  test('jumlah negatif tidak menjadi positif', () {
    final draft = parse('bayar -25000 via BCA', context());
    expect(draft.amount, isNull);
    expect(codes(draft), contains('NEGATIVE_AMOUNT'));
  });
  test('penanda uang/satuan diprioritaskan daripada angka polos', () {
    expect(parse('beli 2000 kopi 35rb via bca', context()).amount, 35000);
    expect(
      codes(parse('beli 2000 kopi 35rb via bca', context())),
      isNot(contains('MULTIPLE_AMOUNTS')),
    );
  });
  test('beberapa jumlah setara memilih pertama dengan warning', () {
    final draft = parse('makan 20rb ongkir 5rb via BCA', context());
    expect(draft.amount, 20000);
    expect(codes(draft), contains('MULTIPLE_AMOUNTS'));
  });
  test('pemisah ambigu menurunkan confidence', () {
    final clear = parse('makan 1234 pakai bca', context());
    final ambiguous = parse('makan 12.34 pakai bca', context());
    expect(ambiguous.amount, 1234);
    expect(codes(ambiguous), contains('AMBIGUOUS_SEPARATOR'));
    expect(ambiguous.confidence, lessThan(clear.confidence));
    final unit = parse('makan 1.000 ribu pakai bca', context());
    expect(unit.amount, 1000);
    expect(codes(unit), contains('AMBIGUOUS_SEPARATOR'));
  });

  final dates = <String, DateTime>{
    'hari ini': DateTime(2026, 10, 8, 10),
    'kemarin': DateTime(2026, 10, 7, 10),
    'kemarin lusa': DateTime(2026, 10, 6, 10),
    'tadi pagi': DateTime(2026, 10, 8, 7),
    'tadi siang': DateTime(2026, 10, 8, 12),
    'tadi sore': DateTime(2026, 10, 8, 16),
    'tadi malam': DateTime(2026, 10, 8, 20),
    'senin lalu': DateTime(2026, 9, 28, 10),
    'hari senin': DateTime(2026, 10, 5, 10),
    'tanggal 5': DateTime(2026, 10, 5, 10),
    '5 oktober': DateTime(2026, 10, 5, 10),
    '5/10': DateTime(2026, 10, 5, 10),
    'minggu lalu': DateTime(2026, 10, 1, 10),
    '': DateTime(2026, 10, 8, 10),
    '5 oktober 2025': DateTime(2025, 10, 5, 10),
    '5/10/2025': DateTime(2025, 10, 5, 10),
  };
  for (final entry in dates.entries) {
    test('tanggal ${entry.key.isEmpty ? 'bawaan' : entry.key}', () {
      final draft = parse('bayar kopi 35000 via BCA ${entry.key}', context());
      expect(draft.occurredAt, entry.value.toUtc());
      expect(draft.occurredAt!.isUtc, isTrue);
      expect(draft.amount, 35000);
    });
  }
  test('tanggal tidak valid tidak bergeser otomatis ke bulan berikut', () {
    final draft = parse('bayar kopi 35000 tanggal 31 februari', context());
    expect(draft.occurredAt, isNull);
    expect(codes(draft), contains('INVALID_DATE'));
    expect(draft.amount, 35000);
  });
  test('tanggal pertama dipilih ketika ada beberapa tanggal', () {
    final draft = parse('kemarin bayar kopi 20rb tanggal 5', context());
    expect(draft.occurredAt, DateTime(2026, 10, 7, 10).toUtc());
    expect(codes(draft), contains('MULTIPLE_DATES'));
  });

  for (final word in [
    'gaji',
    'gajian',
    'bonus',
    'thr',
    'terima',
    'dapat',
    'masuk',
    'refund',
    'cashback',
  ]) {
    test('jenis income: $word', () {
      expect(
        parse('$word 1 juta via bca', context()).type,
        TransactionType.income,
      );
    });
  }
  for (final word in ['transfer', 'pindah', 'tarik tunai', 'setor', 'top up']) {
    test('jenis transfer: $word', () {
      final draft = parse('$word 50rb dari BCA ke GoPay', context());
      expect(draft.type, TransactionType.transfer);
      expect(draft.accountId, 'bca');
      expect(draft.toAccountId, 'gopay');
      expect(draft.categoryId, isNull);
    });
  }
  for (final word in ['beli', 'bayar', 'makan', 'jajan', 'isi', 'langganan']) {
    test('jenis expense: $word', () {
      expect(
        parse('$word 35rb via bca', context()).type,
        TransactionType.expense,
      );
    });
  }
  test('bawaan expense memiliki confidence lebih rendah tanpa kata kerja', () {
    expect(parse('kopi 35rb via bca', context()).type, TransactionType.expense);
    expect(
      parse('kopi 35rb via bca', context()).confidence,
      lessThan(parse('beli kopi 35rb via bca', context()).confidence),
    );
  });
  test('top up menjadi transfer ketika ada dua akun', () {
    final draft = parse('top up GoPay 50rb pakai BCA', context());
    expect(draft.type, TransactionType.transfer);
    expect(draft.accountId, 'bca');
    expect(draft.toAccountId, 'gopay');
    expect(
      parse('top up 50rb via BCA', context()).type,
      TransactionType.expense,
    );
  });
  for (final prefix in ['pakai', 'via', 'dari', 'ke']) {
    test('pola akun: $prefix X', () {
      expect(parse('bayar 35rb $prefix bCa', context()).accountId, 'bca');
    });
  }
  test('alias dan variasi GoPay cocok tanpa menangkap gojek sebagai akun', () {
    expect(parse('bayar 35rb via BANK BCA', context()).accountId, 'bca');
    expect(parse('bayar 35rb pakai go pay', context()).accountId, 'gopay');
    expect(parse('bayar 35rb pakai cash', context()).accountId, 'cash');
    expect(parse('bayar gojek 35rb', context()).accountId, 'cash');
  });
  test('satu salah ketik untuk kata panjang, kata pendek tidak ditebak', () {
    final draft = parse('bayar 35rb via gopai', context());
    expect(draft.accountId, 'gopay');
    expect(codes(draft), contains('FUZZY_ACCOUNT'));
    expect(parse('bayar 35rb via dnaa', context()).accountId, isNull);
    expect(parse('bayar 35rb via gppai', context()).accountId, isNull);
  });
  test('akun terakhir dan warning DEFAULT_ACCOUNT', () {
    final draft = parse('makan 35rb', context(lastAccountId: 'dana'));
    expect(draft.accountId, 'dana');
    expect(codes(draft), contains('DEFAULT_ACCOUNT'));
    expect(parse('makan 35rb', context(lastAccountId: null)).accountId, isNull);
    expect(
      parse('makan 35rb', context(lastAccountId: 'deleted')).accountId,
      isNull,
    );
  });
  test('akun tidak dikenal tidak diam-diam diganti akun terakhir', () {
    final draft = parse('makan 35rb pakai mandiri', context());
    expect(draft.accountId, isNull);
    expect(codes(draft), contains('UNKNOWN_ACCOUNT'));
  });
  test('transfer dengan tujuan saja menggunakan akun terakhir', () {
    final draft = parse('transfer 35rb ke DANA', context(lastAccountId: 'bca'));
    expect(draft.accountId, 'bca');
    expect(draft.toAccountId, 'dana');
    expect(codes(draft), contains('DEFAULT_ACCOUNT'));
  });

  for (final family in CategoryMatcher.dictionary.entries) {
    for (final keyword in family.value) {
      test('kategori ${family.key}: $keyword', () {
        final type = ['gaji', 'refund', 'cashback'].contains(family.key)
            ? TransactionType.income
            : TransactionType.expense;
        expect(
          const CategoryMatcher().match(keyword, context(), type).categoryId,
          family.key,
        );
      });
    }
  }
  test(
    'memori pengguna menang atas kamus; ID lama dan jenis salah diabaikan',
    () {
      final learned = context(
        memory: [
          KeywordMemory(
            keyword: 'kopi',
            categoryId: 'hiburan',
            accountId: 'dana',
            count: 3,
            updatedAt: _now,
          ),
        ],
      );
      expect(parse('beli kopi 20rb via bca', learned).categoryId, 'hiburan');
      final stale = context(
        memory: [
          KeywordMemory(
            keyword: 'kopi',
            categoryId: 'deleted',
            count: 9,
            updatedAt: _now,
          ),
          KeywordMemory(
            keyword: 'kopi',
            categoryId: 'gaji',
            count: 5,
            updatedAt: _now,
          ),
        ],
      );
      expect(parse('beli kopi 20rb via bca', stale).categoryId, 'makanan');
    },
  );
  test('nama Makan & Minum dan subkategori pemasukan dari aplikasi cocok', () {
    final ctx = ParserContext(
      clock: FixedClock(_now),
      accounts: context().accounts,
      categories: [
        const ParserCategory(
          id: 'food',
          name: 'Makan & Minum',
          type: TransactionType.expense,
        ),
        const ParserCategory(
          id: 'salary',
          name: 'Pemasukan • Gaji',
          type: TransactionType.income,
        ),
      ],
    );
    expect(parse('makan kopi 35rb via bca', ctx).categoryId, 'food');
    expect(parse('gaji 2jt via bca', ctx).categoryId, 'salary');
  });
  test('catatan membersihkan jumlah, tanggal, dan akun serta mempertahankan teks asli', () {
    const text = '  Bayar kopi 35.000  pakai BCA kemarin  ';
    final draft = parse(text, context());
    expect(draft.note, 'bayar kopi');
    expect(draft.rawText, text);
    expect(draft.source, DraftSource.text);
  });

  for (final delimiter in [',', ';', ' dan ', ' DAN ']) {
    test('beberapa transaksi dipisah dengan $delimiter', () {
      final drafts = parseMany(
        'beli kopi 20rb via bca$delimiter bayar parkir 5rb via dana',
        context(),
      );
      expect(drafts, hasLength(2));
      expect(drafts.map((d) => d.amount), [20000, 5000]);
      expect(drafts.map((d) => d.accountId), ['bca', 'dana']);
      expect(drafts.map((d) => d.categoryId), ['makanan', 'transport']);
    });
  }
  test('koma desimal/ribuan tidak memecah kalimat', () {
    expect(parseMany('gaji 2,5jt via bca', context()), hasLength(1));
    expect(
      parseMany('beli kopi 35,000 via bca', context()).single.amount,
      35000,
    );
    expect(parseMany('beli 35000,bayar 5000', context()).map((d) => d.amount), [
      35000,
      5000,
    ]);
  });
  test('potongan tanpa jumlah menghasilkan satu draf dengan warning', () {
    final drafts = parseMany('beli kopi 20rb dan roti', context());
    expect(drafts, hasLength(1));
    expect(codes(drafts.single), contains('INCOMPLETE_SPLIT'));
    expect(drafts.single.amount, 20000);
  });
  test(
    'API satu draf memperingatkan multi transaksi, tidak membuang teks asli',
    () {
      const text = 'beli kopi 20rb; bayar parkir 5rb';
      final draft = parse(text, context());
      expect(codes(draft), contains('MULTIPLE_TRANSACTIONS'));
      expect(draft.rawText, text);
    },
  );
  test('confidence sesuai rumus dan selalu dalam 0–1', () {
    expect(
      parse('makan kopi 20rb via bca', context()).confidence,
      closeTo(.95, .000001),
    );
    expect(
      parse('makan kopi 20rb', context()).confidence,
      closeTo(.75, .000001),
    );
    for (final text in [
      '',
      '1,000ribu, hari ini dan kemarin pakai xyz',
      'transfer 2rb ke xyz',
      'kopi',
    ]) {
      expect(parse(text, context()).confidence, inInclusiveRange(0, 1));
    }
  });
  test('AmountParser dapat dipakai sendiri tanpa Flutter', () {
    expect(const AmountParser().parse('2,5jt').amount, 2500000);
  });
  test('satu karakter yang hilang pada nama panjang tetap terdeteksi', () {
    final draft = parse('bayar 35rb via goay', context());
    expect(draft.accountId, 'gopay');
    expect(codes(draft), contains('FUZZY_ACCOUNT'));
  });
  test('akun eksplisit dan terakhir mendahului memori akun', () {
    final memories = [
      KeywordMemory(
        keyword: 'kopi',
        accountId: 'dana',
        count: 3,
        updatedAt: _now,
      ),
    ];
    expect(
      parse('beli kopi 20rb via bca', context(memory: memories)).accountId,
      'bca',
    );
    expect(
      parse(
        'beli kopi 20rb',
        context(memory: memories, lastAccountId: 'gopay'),
      ).accountId,
      'gopay',
    );
    final draft = parse(
      'beli kopi 20rb',
      context(memory: memories, lastAccountId: null),
    );
    expect(draft.accountId, 'dana');
    expect(codes(draft), contains('DEFAULT_ACCOUNT'));
  });
  test('semua draf dalam satu kalimat memakai satu snapshot Clock', () {
    final clock = _AdvancingClock();
    final ctx = ParserContext(
      clock: clock,
      accounts: context().accounts,
      categories: context().categories,
    );
    final drafts = parseMany(
      'beli kopi 20rb via bca; bayar parkir 5rb via dana',
      ctx,
    );
    expect(clock.calls, 1);
    expect(drafts.map((d) => d.occurredAt), everyElement(_now.toUtc()));
  });
}
