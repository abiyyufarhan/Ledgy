import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/features/quick_input/data/quick_input_actions.dart';
import 'package:ledgy/features/quick_input/data/sqlite_quick_input_memory_repository.dart';
import 'package:ledgy/features/quick_input/domain/parser/transaction_parser.dart';
import 'package:ledgy/features/quick_input/domain/quick_input_memory_repository.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';
import 'package:ledgy/features/sync/data/sqlite_sync_store.dart';
import 'package:ledgy/features/sync/domain/sync_models.dart';
import 'package:ledgy/features/transactions/data/repositories/transactions_repository_impl.dart';

final _now = DateTime.utc(2026, 10, 8, 10);
TransactionDraft _original() => TransactionDraft(
  type: TransactionType.expense,
  amount: 20000,
  accountId: 'bca',
  categoryId: 'food',
  occurredAt: _now,
  note: 'beli kopi',
  rawText: 'beli kopi 20rb via BCA',
);

final class _FailAfterLearning implements QuickInputMemoryRepository {
  const _FailAfterLearning(this.inner);
  final QuickInputMemoryRepository inner;
  @override
  Stream<List<KeywordMemory>> watchAll() => inner.watchAll();
  @override
  Future<List<KeywordMemory>> readAll() => inner.readAll();
  @override
  Future<String?> lastAccountId() => inner.lastAccountId();
  @override
  Future<void> learn(
    TransactionDraft original,
    TransactionDraft corrected,
  ) async {
    await inner.learn(original, corrected);
    throw StateError('learning failed');
  }
}

void main() {
  late AppDatabase db;
  late SqliteQuickInputMemoryRepository memory;
  var closed = false;
  setUp(() {
    closed = false;
    db = AppDatabase(NativeDatabase.memory());
    memory = SqliteQuickInputMemoryRepository(db, clock: FixedClock(_now));
  });
  tearDown(() async {
    if (!closed) {
      await db.close();
    }
  });

  test(
    'koreksi menyimpan keyword, kategori, akun, count, dan waktu UTC',
    () async {
      final original = _original();
      final corrected = original.copyWith(
        categoryId: 'hiburan',
        accountId: 'dana',
      );
      await memory.learn(original, corrected);
      final row = (await memory.readAll()).single;
      expect(row.keyword, 'kopi');
      expect(row.categoryId, 'hiburan');
      expect(row.accountId, 'dana');
      expect(row.count, 1);
      expect(row.updatedAt, _now);
      expect(row.updatedAt.isUtc, isTrue);
      await memory.learn(original, corrected);
      expect((await memory.readAll()).single.count, 2);
    },
  );
  test('draf tanpa koreksi tidak mengajari kembali tebakan parser', () async {
    final original = _original();
    await memory.learn(original, original.copyWith());
    expect(await memory.readAll(), isEmpty);
  });
  test('koreksi jumlah saja juga mencatat pilihan kategori dan akun', () async {
    await memory.learn(_original(), _original().copyWith(amount: 25000));
    expect((await memory.readAll()).single.categoryId, 'food');
  });
  test(
    'catatan kata umum saja tidak menghasilkan memori yang menyesatkan',
    () async {
      final original = _original().copyWith(note: 'bayar dari pakai via');
      await memory.learn(original, original.copyWith(amount: 1000));
      expect(await memory.readAll(), isEmpty);
    },
  );
  test('count tidak kehilangan pembaruan pada koreksi bersamaan', () async {
    await Future.wait([
      for (var i = 0; i < 6; i++)
        memory.learn(_original(), _original().copyWith(categoryId: 'hiburan')),
    ]);
    expect((await memory.readAll()).single.count, 6);
  });
  test('pilihan yang dipelajari mengubah hasil parser berikutnya', () async {
    await memory.learn(
      _original(),
      _original().copyWith(categoryId: 'hiburan'),
    );
    final ctx = ParserContext(
      clock: FixedClock(_now),
      accounts: [ParserAccount(id: 'bca', name: 'BCA')],
      categories: [
        const ParserCategory(
          id: 'food',
          name: 'Makanan',
          type: TransactionType.expense,
        ),
        const ParserCategory(
          id: 'hiburan',
          name: 'Hiburan',
          type: TransactionType.expense,
        ),
      ],
      memory: await memory.readAll(),
    );
    expect(parse('beli kopi 20rb via bca', ctx).categoryId, 'hiburan');
  });
  test(
    'simpan transaksi dan memori atomik, kegagalan tidak menimbulkan duplikat',
    () async {
      final transactions = TransactionActions(
        TransactionsRepository(db.transactionsDao),
      );
      final corrected = _original().copyWith(categoryId: 'hiburan');
      final failing = QuickInputActions(
        db,
        transactions,
        _FailAfterLearning(memory),
      );
      await expectLater(
        failing.save(original: _original(), corrected: corrected),
        throwsStateError,
      );
      expect(await db.transactionsDao.watchActive().first, isEmpty);
      expect(await memory.readAll(), isEmpty);
      expect(await SqliteSyncStore(db).dirty(SyncTable.transactions), isEmpty);
      await QuickInputActions(
        db,
        transactions,
        memory,
      ).save(original: _original(), corrected: corrected);
      expect(await db.transactionsDao.watchActive().first, hasLength(1));
      expect((await memory.readAll()).single.count, 1);
      expect(
        await SqliteSyncStore(db).dirty(SyncTable.transactions),
        hasLength(1),
      );
    },
  );
  test('memori tidak masuk antrean sinkronisasi atau tabel server', () async {
    await memory.learn(
      _original(),
      _original().copyWith(categoryId: 'hiburan'),
    );
    for (final table in SyncTable.values) {
      final rows = await SqliteSyncStore(db).dirty(table);
      expect(rows.where((row) => row.data.containsKey('keyword')), isEmpty);
    }
    final triggers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='quick_input_memory'",
        )
        .get();
    expect(triggers, isEmpty);
  });
  test(
    'akun terakhir berasal dari penggunaan terbaru, bukan tanggal kejadian',
    () async {
      final transactions = TransactionActions(
        TransactionsRepository(db.transactionsDao),
      );
      await transactions.save(
        type: 'expense',
        amount: 1000,
        accountId: 'bca',
        categoryId: 'food',
        occurredAt: _now,
      );
      await transactions.save(
        type: 'expense',
        amount: 1000,
        accountId: 'dana',
        categoryId: 'food',
        occurredAt: DateTime.utc(2020),
      );
      expect(await memory.lastAccountId(), 'dana');
    },
  );
  test('migrasi v2 ke v3 mempertahankan transaksi dan memori bertahan saat dibuka ulang', () async {
    await db.close();
    closed = true;
    final folder = await Directory.systemTemp.createTemp(
      'ledgy-parser-migration-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/ledger.sqlite');
    final previous = AppDatabase(NativeDatabase(file));
    await TransactionActions(TransactionsRepository(previous.transactionsDao))
        .save(
          id: 'old-ledger',
          type: 'expense',
          amount: 12500,
          accountId: 'bca',
          categoryId: 'food',
          occurredAt: _now,
        );
    await previous.customStatement('DROP TABLE quick_input_memory');
    await previous.customStatement('PRAGMA user_version = 2');
    await previous.close();
    final migrated = AppDatabase(NativeDatabase(file));
    final local = SqliteQuickInputMemoryRepository(
      migrated,
      clock: FixedClock(_now),
    );
    expect(
      (await migrated.transactionsDao.watchActive().first).single.amount,
      12500,
    );
    expect(await local.readAll(), isEmpty);
    await local.learn(_original(), _original().copyWith(categoryId: 'hiburan'));
    await migrated.close();
    final reopened = AppDatabase(NativeDatabase(file));
    try {
      expect(
        (await SqliteQuickInputMemoryRepository(
          reopened,
        ).readAll()).single.categoryId,
        'hiburan',
      );
      expect(
        (await reopened.transactionsDao.watchActive().first).single.id,
        'old-ledger',
      );
      expect(
        (await reopened.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        4,
      );
    } finally {
      await reopened.close();
    }
  });
}
