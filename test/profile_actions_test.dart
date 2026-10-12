import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/features/auth/data/profile_actions.dart';
import 'package:ledgy/features/auth/domain/auth_repository.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/sync/data/sqlite_sync_store.dart';
import 'package:ledgy/features/sync/domain/sync_models.dart';
import 'package:ledgy/features/sync/domain/sync_service.dart';

import 'support/profile_auth.dart';
import 'support/sync_server.dart';

void main() {
  late AppDatabase db;
  late ProfileTestAuth auth;
  late LocalFinanceRepository finance;
  late SyncService sync;
  late SyncTestServer server;
  late ProfileActions actions;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    finance = LocalFinanceRepository(db);
    auth = ProfileTestAuth();
    final account = (await finance.snapshot()).accounts.first;
    await db.transactionsDao.save(
      TransactionsCompanion.insert(
        id: 'old-tx',
        type: 'expense',
        amount: 100,
        accountId: account.id,
        occurredAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await finance.setState('sync:owner', auth.currentUser!.id);
    await finance.setState('sync:project', 'test');
    await finance.setState('dashboard:savings-goals:v1', '[{"id":"goal"}]');
    await finance.setState('parser:record_failures', 'true');
    await db.customStatement('INSERT INTO parser_failures(text) VALUES (?)', [
      'kopi tanpa jumlah',
    ]);
    await db
        .into(db.quickInputMemory)
        .insert(
          QuickInputMemoryCompanion.insert(
            keyword: 'kopi',
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    server = SyncTestServer();
    sync = SyncService(
      local: SqliteSyncStore(db),
      remote: server,
      userId: () => auth.currentUser?.id,
      project: 'test',
    );
    actions = ProfileActions(auth, finance, sync);
  });
  tearDown(() async {
    await sync.dispose();
    await auth.events.close();
    await db.close();
  });

  test(
    'reset mengosongkan ledger aktif dan menyimpan tombstone untuk sinkron',
    () async {
      await actions.resetData();
      expect(
        await db.customSelect('SELECT text FROM parser_failures').get(),
        isEmpty,
      );
      expect(await finance.state('parser:record_failures'), isNull);
      expect(await db.select(db.quickInputMemory).get(), isEmpty);
      final snapshot = await finance.snapshot();
      expect(snapshot.transactions.where((t) => t.deletedAt == null), isEmpty);
      final transaction = await db.select(db.transactions).getSingle();
      expect(transaction.deletedAt, isNotNull);
      expect(transaction.isDirty, isTrue);
      final dirty = await SqliteSyncStore(db).dirty(SyncTable.transactions);
      expect(dirty.single.data['deleted_at'], isNotNull);
      expect(await finance.state('sync:owner'), 'profile-owner');
      expect(await finance.state('dashboard:savings-goals:v1'), '[]');
      expect(auth.currentUser!.name, 'Abiyyu Farhan');
      final accounts = await db.accountsDao.watchActive().first;
      expect(accounts.single.name, 'Tunai');
      expect(accounts.single.initialBalance, 0);
      expect(accounts.single.isDirty, isTrue);
      await sync.sync();
      expect(sync.status.phase, SyncPhase.synced);
      expect(
        server.rows[SyncTable.transactions]!['old-tx']!['deleted_at'],
        isNotNull,
      );
      final otherDb = AppDatabase(NativeDatabase.memory());
      final otherSync = SyncService(
        local: SqliteSyncStore(otherDb),
        remote: server,
        userId: () => auth.currentUser?.id,
        project: 'test',
      );
      try {
        await otherSync.sync();
        expect(await otherDb.transactionsDao.watchActive().first, isEmpty);
        expect(
          (await otherDb.accountsDao.watchActive().first).single.name,
          'Tunai',
        );
        expect(otherSync.status.phase, SyncPhase.synced);
      } finally {
        await otherSync.dispose();
        await otherDb.close();
      }
    },
  );
  test('gagal menghapus akun tidak menyentuh data lokal', () async {
    auth.failure = 'Cloud belum siap.';
    await expectLater(actions.deleteAccount(), throwsA(isA<AuthFailure>()));
    expect((await db.select(db.transactions).getSingle()).deletedAt, isNull);
    expect(await finance.state('sync:owner'), 'profile-owner');
    expect(auth.currentUser, isNotNull);
    expect(await db.select(db.quickInputMemory).get(), hasLength(1));
    expect(
      await db.customSelect('SELECT text FROM parser_failures').get(),
      hasLength(1),
    );
  });
  test(
    'penghapusan akun yang berhasil membersihkan owner dan data perangkat',
    () async {
      await actions.deleteAccount();
      expect(
        await db.customSelect('SELECT text FROM parser_failures').get(),
        isEmpty,
      );
      expect(await finance.state('parser:record_failures'), isNull);
      expect(await db.select(db.quickInputMemory).get(), isEmpty);
      expect(auth.deletions, 1);
      expect(auth.currentUser, isNull);
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await finance.state('sync:owner'), isNull);
      expect(await finance.state('dashboard:savings-goals:v1'), isNull);
      expect((await db.accountsDao.watchActive().first).single.name, 'Tunai');
    },
  );
  test('aksi akun tidak dapat menghapus ledger milik akun lain', () async {
    await finance.setState('sync:owner', 'other-owner');
    await expectLater(actions.resetData(), throwsA(isA<AuthFailure>()));
    await expectLater(actions.deleteAccount(), throwsA(isA<AuthFailure>()));
    expect(auth.deletions, 0);
    expect((await db.select(db.transactions).getSingle()).deletedAt, isNull);
  });
}
