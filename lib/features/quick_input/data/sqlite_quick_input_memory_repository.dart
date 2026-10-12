import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/parser/normalizer.dart';
import '../domain/parser/parser_context.dart';
import '../domain/quick_input_memory_repository.dart';
import '../domain/transaction_draft.dart';

final class SqliteQuickInputMemoryRepository
    implements QuickInputMemoryRepository {
  const SqliteQuickInputMemoryRepository(
    this.db, {
    this.clock = const SystemClock(),
  });
  final AppDatabase db;
  final Clock clock;

  List<KeywordMemory> _map(List<QuickInputMemoryRow> rows) =>
      List.unmodifiable([
        for (final row in rows)
          KeywordMemory(
            keyword: row.keyword,
            categoryId: row.categoryId,
            accountId: row.accountId,
            count: row.count,
            updatedAt: row.updatedAt.toUtc(),
          ),
      ]);

  @override
  Stream<List<KeywordMemory>> watchAll() =>
      db.select(db.quickInputMemory).watch().map(_map);
  @override
  Future<List<KeywordMemory>> readAll() async =>
      _map(await db.select(db.quickInputMemory).get());
  @override
  Future<String?> lastAccountId() async =>
      (await (db.select(db.transactions)
                ..where((t) => t.deletedAt.isNull())
                ..orderBy([
                  (t) => OrderingTerm.desc(t.updatedAt),
                  (t) =>
                      OrderingTerm.desc(const CustomExpression<int>('rowid')),
                ])
                ..limit(1))
              .getSingleOrNull())
          ?.accountId;

  static const _stopWords = {
    'beli',
    'bayar',
    'transfer',
    'pindah',
    'terima',
    'dapat',
    'masuk',
    'isi',
    'dari',
    'pakai',
    'via',
    'dan',
    'untuk',
    'dengan',
    'yang',
    'hari',
    'tanggal',
    'ini',
    'kemarin',
    'lusa',
    'tadi',
    'pagi',
    'siang',
    'sore',
    'malam',
    'lalu',
    'top',
    'rupiah',
    'nol',
    'satu',
    'dua',
    'tiga',
    'empat',
    'lima',
    'enam',
    'tujuh',
    'delapan',
    'sembilan',
    'puluh',
    'belas',
    'ratus',
    'seratus',
    'sepuluh',
    'sebelas',
    'ribu',
    'juta',
    'setengah',
    'sejuta',
    'seribu',
  };

  @override
  Future<void> learn(
    TransactionDraft original,
    TransactionDraft corrected,
  ) async {
    final changed =
        original.type != corrected.type ||
        original.amount != corrected.amount ||
        original.accountId != corrected.accountId ||
        original.toAccountId != corrected.toAccountId ||
        original.recipientName != corrected.recipientName ||
        original.recipientAccount != corrected.recipientAccount ||
        original.categoryId != corrected.categoryId ||
        original.note != corrected.note ||
        original.occurredAt != corrected.occurredAt;
    if (!changed) {
      return;
    }
    final text = const Normalizer().normalize(
      corrected.note ?? original.note ?? original.rawText,
    );
    final words = RegExp(r'[a-z]{3,}')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .where((word) => !_stopWords.contains(word))
        .toList();
    final keywords = <String>{
      ...words,
      for (var i = 0; i + 1 < words.length; i++) '${words[i]} ${words[i + 1]}',
    };
    final categoryId = corrected.type == TransactionType.transfer
        ? null
        : corrected.categoryId;
    if (categoryId == null && corrected.accountId == null) return;
    await db.transaction(() async {
      for (final keyword in keywords) {
        final old = await (db.select(
          db.quickInputMemory,
        )..where((m) => m.keyword.equals(keyword))).getSingleOrNull();
        await db
            .into(db.quickInputMemory)
            .insertOnConflictUpdate(
              QuickInputMemoryCompanion.insert(
                keyword: keyword,
                categoryId: Value(categoryId ?? old?.categoryId),
                accountId: Value(corrected.accountId ?? old?.accountId),
                count: Value((old?.count ?? 0) + 1),
                updatedAt: clock.now().toUtc(),
              ),
            );
      }
    });
  }
}
