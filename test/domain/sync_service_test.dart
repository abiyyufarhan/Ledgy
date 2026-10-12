import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/sync/data/sqlite_sync_store.dart';
import 'package:ledgy/features/sync/domain/sync_models.dart';
import 'package:ledgy/features/sync/domain/sync_service.dart';
import 'package:uuid/uuid.dart';

import '../support/sync_server.dart';

class _Device {
  _Device(this.db, this.server) {
    store = SqliteSyncStore(db);
    service = SyncService(
      local: store,
      remote: server,
      userId: () => owner,
      project: 'test-project',
      pageSize: pageSize,
    );
  }
  final AppDatabase db;
  final SyncTestServer server;
  final int pageSize = 2;
  String? owner = syncUser;
  late final SqliteSyncStore store;
  late final SyncService service;
  Future<void> close() async {
    await service.dispose();
    await db.close();
  }
}

Future<_Device> _device(
  SyncTestServer server, {
  bool starter = false,
  File? file,
}) async {
  final db = AppDatabase(
    file == null ? NativeDatabase.memory() : NativeDatabase(file),
  );
  await db.select(db.accounts).get();
  if (!starter && file == null) {
    await db.delete(db.recurringRules).go();
    await db.delete(db.budgets).go();
    await db.delete(db.transactions).go();
    await db.delete(db.categories).go();
    await db.delete(db.accounts).go();
  }
  final device = _Device(db, server);
  addTearDown(device.close);
  return device;
}

Future<void> _ledger(
  _Device device, {
  bool allTables = false,
  DateTime? deviceClock,
}) async {
  final db = device.db;
  final now = deviceClock ?? DateTime.utc(2026, 10, 2);
  await db.accountsDao.save(
    AccountsCompanion.insert(
      id: walletId,
      name: 'Bank Jago',
      initialBalance: const Value(3000000000),
      createdAt: now,
      updatedAt: now,
    ),
  );
  await db.categoriesDao.save(
    CategoriesCompanion.insert(
      id: categoryId,
      name: 'Uji',
      createdAt: now,
      updatedAt: now,
    ),
  );
  await db.transactionsDao.save(
    TransactionsCompanion.insert(
      id: transactionId,
      type: 'expense',
      amount: 200000,
      accountId: walletId,
      categoryId: const Value(categoryId),
      note: const Value('J.CO'),
      occurredAt: now,
      createdAt: now,
      updatedAt: now,
    ),
  );
  if (allTables) {
    await db.budgetsDao.save(
      BudgetsCompanion.insert(
        id: budgetId,
        categoryId: categoryId,
        amount: 1000000,
        monthStart: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.recurringRulesDao.save(
      RecurringRulesCompanion.insert(
        id: ruleId,
        type: 'expense',
        amount: 50000,
        accountId: walletId,
        categoryId: const Value(categoryId),
        frequency: 'monthly',
        nextOccurrenceAt: DateTime.utc(2027),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

Future<void> _edit(_Device d, String name, DateTime time) =>
    (d.db.update(d.db.accounts)..where((a) => a.id.equals(walletId))).write(
      AccountsCompanion(
        name: Value(name),
        updatedAt: Value(time),
        isDirty: const Value(true),
      ),
    );
Future<Account> _wallet(_Device d) => (d.db.select(
  d.db.accounts,
)..where((a) => a.id.equals(walletId))).getSingle();

void main() {
  test(
    'maintenance menunggu upload dan menahan sinkron sampai selesai',
    () async {
      final server = SyncTestServer();
      final device = await _device(server);
      await _ledger(device);
      final uploadStarted = Completer<void>();
      final releaseUpload = Completer<void>();
      server.beforePush = (_) async {
        if (!uploadStarted.isCompleted) {
          uploadStarted.complete();
          await releaseUpload.future;
        }
      };
      final upload = device.service.sync();
      await uploadStarted.future;
      final maintenanceStarted = Completer<void>();
      final releaseMaintenance = Completer<void>();
      final maintenance = device.service.withMaintenance(() async {
        maintenanceStarted.complete();
        await releaseMaintenance.future;
      });
      await device.service.sync();
      expect(maintenanceStarted.isCompleted, isFalse);
      releaseUpload.complete();
      await upload;
      await maintenanceStarted.future;
      final calls = server.windowCalls;
      await device.service.sync();
      expect(server.windowCalls, calls);
      releaseMaintenance.complete();
      await maintenance;
      await device.service.sync();
      expect(server.windowCalls, greaterThan(calls));
      await expectLater(
        device.service.withMaintenance(() async => throw StateError('failed')),
        throwsStateError,
      );
      final afterFailure = server.windowCalls;
      await device.service.sync();
      expect(server.windowCalls, greaterThan(afterFailure));
    },
  );

  test('detail penerima transfer tersinkron antarperangkat', () async {
    final server = SyncTestServer();
    final a = await _device(server);
    await _ledger(a);
    await (a.db.update(
      a.db.transactions,
    )..where((t) => t.id.equals(transactionId))).write(
      const TransactionsCompanion(
        type: Value('transfer'),
        categoryId: Value(null),
        recipientName: Value('Budi'),
        recipientAccount: Value('0012345678'),
      ),
    );
    await a.service.sync();
    final b = await _device(server);
    await b.service.sync();
    final received = await b.db.select(b.db.transactions).getSingle();
    expect(received.recipientName, 'Budi');
    expect(received.recipientAccount, '0012345678');
    expect(received.toAccountId, isNull);
    expect(b.service.status.phase, SyncPhase.synced);
  });
  test('dua perangkat: perubahan terakhir diterima server menang walau jam perangkat berbeda', () async {
    final server = SyncTestServer();
    final a = await _device(server);
    await _ledger(a);
    await a.service.sync();
    final b = await _device(server);
    await b.service.sync();
    await _edit(a, 'Dari A', DateTime.utc(2000));
    await _edit(b, 'Dari B', DateTime.utc(2099));
    final entered = Completer<void>(), release = Completer<void>();
    server.beforePush = (row) async {
      if (row.data['name'] == 'Dari A') {
        entered.complete();
        await release.future;
      }
    };
    final pending = a.service.sync();
    await entered.future;
    await b.service.sync();
    release.complete();
    await pending;
    server.beforePush = null;
    await b.service.sync();
    expect((await _wallet(a)).name, 'Dari A');
    expect((await _wallet(b)).name, 'Dari A');
    expect(server.rows[SyncTable.accounts]![walletId]!['name'], 'Dari A');
    expect(a.service.status.phase, SyncPhase.synced);
    expect((await _wallet(a)).updatedAt.year, 2026);
  });

  test('penghapusan di satu perangkat menyebar sebagai tombstone tanpa menghapus historis', () async {
    final server = SyncTestServer();
    final a = await _device(server);
    await _ledger(a);
    await a.service.sync();
    final b = await _device(server);
    await b.service.sync();
    await a.db.transactionsDao.softDelete(transactionId, DateTime.utc(2099));
    await a.service.sync();
    await b.service.sync();
    final row = await b.db.select(b.db.transactions).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(await b.db.transactionsDao.watchActive().first, isEmpty);
    expect(row.isDirty, isFalse);
    expect(
      server.rows[SyncTable.transactions]![transactionId]!['deleted_at'],
      isNotNull,
    );
    await b.db.transactionsDao.restore(transactionId, DateTime.utc(2000));
    await b.service.sync();
    await a.service.sync();
    expect(
      (await a.db.select(a.db.transactions).getSingle()).deletedAt,
      isNull,
    );
  });

  test('sinkron pertama perangkat baru: seluruh lima tabel tanpa duplikat data contoh', () async {
    final server = SyncTestServer();
    final a = await _device(server);
    await _ledger(a, allTables: true);
    await a.service.sync();
    final b = await _device(server, starter: true);
    expect((await b.db.select(b.db.accounts).getSingle()).name, 'Tunai');
    final pushes = server.pushed.length;
    await b.service.sync();
    expect(
      server.pushed.length,
      pushes,
      reason: 'starter data must not be uploaded',
    );
    expect((await b.db.select(b.db.accounts).getSingle()).id, walletId);
    expect((await b.db.select(b.db.categories).getSingle()).id, categoryId);
    expect(
      (await b.db.select(b.db.transactions).getSingle()).id,
      transactionId,
    );
    expect((await b.db.select(b.db.budgets).getSingle()).id, budgetId);
    expect((await b.db.select(b.db.recurringRules).getSingle()).id, ruleId);
    expect((await b.store.queue()).pending, 0);
    expect((await _wallet(b)).initialBalance, 3000000000);
    expect(await b.store.cursor(), isNotNull);
  });

  test(
    'parent dikirim dahulu, termasuk seed legacy yang awalnya is_dirty=false',
    () async {
      final server = SyncTestServer();
      final d = await _device(server, starter: true);
      final cash = await d.db.select(d.db.accounts).getSingle();
      final category = (await d.db.select(d.db.categories).get()).first;
      final now = DateTime.utc(2026);
      await d.db.transactionsDao.save(
        TransactionsCompanion.insert(
          id: transactionId,
          type: 'expense',
          amount: 100,
          accountId: cash.id,
          categoryId: Value(category.id),
          occurredAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await d.service.sync();
      expect(d.service.status.phase, SyncPhase.synced);
      expect(
        server.pushed.indexOf(SyncTable.accounts),
        lessThan(server.pushed.indexOf(SyncTable.transactions)),
      );
      expect(
        server.pushed.indexOf(SyncTable.categories),
        lessThan(server.pushed.indexOf(SyncTable.transactions)),
      );
      expect(server.rows[SyncTable.accounts]!.containsKey(cash.id), isTrue);
    },
  );

  test('edit dalam detik yang sama saat upload berlangsung tidak dibersihkan oleh ack lama', () async {
    final server = SyncTestServer();
    final d = await _device(server);
    await _ledger(d);
    await d.service.sync();
    final time = DateTime.utc(2026, 10, 2, 12);
    await _edit(d, 'Snapshot dikirim', time);
    final entered = Completer<void>(), release = Completer<void>();
    server.afterPush = (row) async {
      if (row.id == walletId) {
        entered.complete();
        await release.future;
      }
    };
    final flight = d.service.sync();
    await entered.future;
    await _edit(d, 'Edit terbaru', time);
    release.complete();
    await flight;
    expect((await _wallet(d)).name, 'Edit terbaru');
    expect((await _wallet(d)).isDirty, isTrue);
    expect(d.service.status.phase, SyncPhase.waiting);
    server.afterPush = null;
    await d.service.sync();
    expect(server.rows[SyncTable.accounts]![walletId]!['name'], 'Edit terbaru');
    expect((await d.store.queue()).pending, 0);
  });

  test(
    'respons hilang sesudah commit: retry idempotent dan antrean tidak hilang',
    () async {
      final server = SyncTestServer();
      final d = await _device(server);
      await _ledger(d);
      await d.service.sync();
      await _edit(d, 'Offline edit', DateTime.utc(2099));
      server.afterPush = (_) async => throw const SyncOffline();
      await d.service.sync();
      expect(d.service.status.phase, SyncPhase.waiting);
      expect((await _wallet(d)).isDirty, isTrue);
      server.afterPush = null;
      await d.service.sync();
      expect(server.rows[SyncTable.accounts]!.length, 1);
      expect((await d.store.queue()).pending, 0);
    },
  );

  test(
    'gagal pull tidak memajukan cursor; retry mengambil halaman tersisa',
    () async {
      final server = SyncTestServer();
      final a = await _device(server);
      await _ledger(a, allTables: true);
      await a.service.sync();
      final b = await _device(server);
      server.failPull = SyncTable.transactions;
      await b.service.sync();
      expect(b.service.status.phase, SyncPhase.failed);
      expect(await b.store.cursor(), isNull);
      expect((await b.db.select(b.db.accounts).get()).length, 1);
      server.failPull = null;
      await b.service.sync();
      expect((await b.db.select(b.db.transactions).get()).length, 1);
      expect((await b.db.select(b.db.recurringRules).get()).length, 1);
      expect(b.service.status.phase, SyncPhase.synced);
    },
  );

  test('pagination timestamp sama lebih dari satu halaman dan microsecond server dipertahankan', () async {
    final server = SyncTestServer();
    final a = await _device(server);
    await _ledger(a);
    await a.service.sync();
    final original = server.rows[SyncTable.categories]![categoryId]!;
    final sharedTime = server.clock;
    for (var i = 0; i < 9; i++) {
      final id = const Uuid().v4();
      server.rows[SyncTable.categories]![id] = {
        ...original,
        'id': id,
        'name': 'Kategori $i',
        'updated_at': sharedTime.toIso8601String(),
      };
    }
    final b = await _device(server);
    await b.service.sync();
    expect((await b.db.select(b.db.categories).get()).length, 10);
    final updated = {
      ...server.rows[SyncTable.accounts]![walletId]!,
      'name': 'Microsecond baru',
      'updated_at': server.clock
          .add(const Duration(microseconds: 1))
          .toIso8601String(),
    };
    server.rows[SyncTable.accounts]![walletId] = updated;
    await b.service.sync();
    expect((await _wallet(b)).name, 'Microsecond baru');
  });

  test('cursor pull tidak melompat ke timestamp hasil push dan melewatkan perubahan lain', () async {
    final server = SyncTestServer();
    final a = await _device(server);
    await _ledger(a);
    await a.service.sync();
    final b = await _device(server);
    await b.service.sync();
    server.clock = server.clock.add(const Duration(minutes: 10));
    await (a.db.update(
      a.db.transactions,
    )..where((t) => t.id.equals(transactionId))).write(
      const TransactionsCompanion(
        note: Value('Dari perangkat A'),
        isDirty: Value(true),
      ),
    );
    await a.service.sync();
    await _edit(b, 'Push lebih baru', DateTime.utc(2099));
    await b.service.sync();
    expect(
      (await b.db.select(b.db.transactions).getSingle()).note,
      'Dari perangkat A',
    );
  });

  test('satu flight untuk trigger manual dan otomatis bersamaan', () async {
    final server = SyncTestServer();
    final d = await _device(server);
    await _ledger(d);
    final a = d.service.sync(), b = d.service.sync();
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);
    expect(
      server.pushed.where((table) => table == SyncTable.transactions).length,
      1,
    );
  });

  test('tanpa login tidak menghubungi cloud, antrean tetap ada', () async {
    final server = SyncTestServer();
    final d = await _device(server);
    await _ledger(d);
    d.owner = null;
    await d.service.sync();
    expect(server.windowCalls, 0);
    expect(d.service.status.phase, SyncPhase.local);
    expect((await d.store.queue()).pending, 3);
  });

  test(
    'akun/proyek berbeda tidak menerima data akun yang sudah tertaut',
    () async {
      final server = SyncTestServer();
      final d = await _device(server);
      await _ledger(d);
      await d.service.sync();
      await _edit(d, 'Privat', DateTime.utc(2026));
      d.owner = otherSyncUser;
      final count = server.pushed.length;
      await d.service.sync();
      expect(d.service.status.phase, SyncPhase.failed);
      expect(server.pushed.length, count);
      expect((await _wallet(d)).isDirty, isTrue);
      final otherProject = SyncService(
        local: d.store,
        remote: server,
        userId: () => syncUser,
        project: 'another-project',
      );
      addTearDown(otherProject.dispose);
      await otherProject.sync();
      expect(otherProject.status.phase, SyncPhase.failed);
    },
  );

  test(
    'logout saat request berjalan tidak menerapkan respons ke sesi berikutnya',
    () async {
      final server = SyncTestServer();
      final d = await _device(server);
      await _ledger(d);
      server.afterPush = (_) async {
        d.owner = null;
      };
      await d.service.sync();
      expect(d.service.status.phase, SyncPhase.local);
      expect((await _wallet(d)).isDirty, isTrue);
      expect(await d.store.cursor(), isNull);
    },
  );

  test(
    'antrean dan cursor bertahan setelah database serta aplikasi ditutup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ledgy-sync-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/ledger.sqlite');
      final server = SyncTestServer();
      final first = _Device(AppDatabase(NativeDatabase(file)), server);
      await _ledger(first);
      await first.service.sync();
      final cursor = await first.store.cursor();
      await _edit(first, 'Tersimpan offline', DateTime.utc(2099));
      server.offline = true;
      await first.service.sync();
      await first.close();
      final second = _Device(AppDatabase(NativeDatabase(file)), server);
      addTearDown(second.close);
      expect(await second.store.cursor(), cursor);
      expect((await _wallet(second)).name, 'Tersimpan offline');
      expect((await second.store.queue()).pending, greaterThan(0));
      server.offline = false;
      await second.service.sync();
      expect(
        server.rows[SyncTable.accounts]![walletId]!['name'],
        'Tersimpan offline',
      );
      expect((await second.store.queue()).pending, 0);
    },
  );

  test('dua perangkat memproses kejadian transaksi berulang yang sama tanpa duplikat', () async {
    final server = SyncTestServer();
    final a = await _device(server);
    await _ledger(a, allTables: true);
    final due = DateTime.utc(2026, 10, 2, 12);
    await (a.db.update(
      a.db.recurringRules,
    )..where((r) => r.id.equals(ruleId))).write(
      RecurringRulesCompanion(
        nextOccurrenceAt: Value(due),
        isDirty: const Value(true),
      ),
    );
    await a.service.sync();
    final b = await _device(server);
    await b.service.sync();
    await LocalFinanceRepository(a.db).generateDue(due);
    await LocalFinanceRepository(b.db).generateDue(due);
    await a.service.sync();
    await b.service.sync();
    await a.service.sync();
    expect(
      server.rows[SyncTable.transactions]!.length,
      2,
      reason: 'one manual + one recurring',
    );
    final generated = (await a.db.select(a.db.transactions).get())
        .where((t) => t.id != transactionId)
        .single;
    expect(generated.id[14], '4');
    expect((await b.db.select(b.db.transactions).get()).length, 2);
  });
}
