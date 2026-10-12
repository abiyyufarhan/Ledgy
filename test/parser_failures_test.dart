import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/quick_input/data/sqlite_parser_failure_repository.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_pipeline.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

import 'support/parser_corpus.dart';

void main() {
  late AppDatabase db;
  late SqliteParserFailureRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SqliteParserFailureRepository(LocalFinanceRepository(db));
  });
  tearDown(() => db.close());
  test(
    'bawaan mati, opt-in hanya kegagalan, dedup, ekspor hanya teks',
    () async {
      final ctx = corpusContext();
      const parser = ParserPipeline();
      final bad = await parser.parse('makan tanpa jumlah', ctx);
      expect(await repo.enabled(), isFalse);
      await repo.record('makan tanpa jumlah', bad, ctx);
      expect(await repo.readAll(), isEmpty);
      await repo.setEnabled(true);
      await repo.record('makan tanpa jumlah', bad, ctx);
      await repo.record('makan tanpa jumlah', bad, ctx);
      for (final source in [DraftSource.voice, DraftSource.receipt]) {
        await repo.record('teks privat $source', [
          bad.single.copyWith(source: source),
        ], ctx);
      }
      await repo.record(
        'makan 35rb pakai BCA',
        await parser.parse('makan 35rb pakai BCA', ctx),
        ctx,
      );
      expect(await repo.readAll(), ['makan tanpa jumlah']);
      expect(jsonDecode(jsonEncode(await repo.readAll())), [
        'makan tanpa jumlah',
      ]);
      final columns = await db
          .customSelect('PRAGMA table_info(parser_failures)')
          .get();
      expect(columns.map((r) => r.read<String>('name')), ['text']);
      final sync = await db
          .customSelect(
            "SELECT * FROM ledgy_sync_rows WHERE table_name='parser_failures'",
          )
          .get();
      expect(sync, isEmpty);
      await repo.setEnabled(false);
      await repo.record('jangan disimpan', [], ctx);
      expect(await repo.readAll(), ['makan tanpa jumlah']);
      await repo.clear();
      expect(await repo.readAll(), isEmpty);
    },
  );
  test('catatan dibatasi 500 teks, kosong diabaikan', () async {
    await repo.setEnabled(true);
    final ctx = corpusContext();
    await repo.record('   ', [], ctx);
    for (var i = 0; i < 505; i++) {
      await repo.record('kalimat $i', [], ctx);
    }
    final rows = await repo.readAll();
    expect(rows.length, 500);
    expect(rows.first, 'kalimat 504');
    expect(rows.last, 'kalimat 5');
  });
  test(
    'migrasi v3 mempertahankan ledger dan membuat tabel diagnostik',
    () async {
      await db.close();
      final directory = await Directory.systemTemp.createTemp(
        'ledgy2-parser-migration-',
      );
      final path = File('${directory.path}/migration.sqlite');
      final old = AppDatabase(NativeDatabase(path));
      final account = (await old.accountsDao.watchActive().first).first;
      await old.customStatement('DROP TABLE parser_failures');
      await old.customStatement('PRAGMA user_version=3');
      await old.close();
      final migrated = AppDatabase(NativeDatabase(path));
      try {
        expect(
          (await migrated.accountsDao.watchActive().first).any(
            (a) => a.id == account.id,
          ),
          isTrue,
        );
        expect(
          await migrated.customSelect('SELECT text FROM parser_failures').get(),
          isEmpty,
        );
        expect(
          (await migrated.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          4,
        );
      } finally {
        await migrated.close();
        final root = directory.absolute.path;
        if (!root.startsWith(Directory.systemTemp.absolute.path) ||
            !directory.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('ledgy2-parser-migration-')) {
          throw StateError('Unsafe temp path');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
