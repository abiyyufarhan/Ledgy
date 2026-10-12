import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/sync_models.dart';

class SqliteSyncStore implements SyncLocalStore {
  SqliteSyncStore(this.db);
  final AppDatabase db;

  TableInfo _table(SyncTable table) => switch (table) {
    SyncTable.accounts => db.accounts,
    SyncTable.categories => db.categories,
    SyncTable.transactions => db.transactions,
    SyncTable.budgets => db.budgets,
    SyncTable.recurringRules => db.recurringRules,
  };

  Future<String?> _state(String key) async =>
      (await db
              .customSelect(
                'SELECT value FROM ledgy_local_state WHERE key=?',
                variables: [Variable(key)],
              )
              .getSingleOrNull())
          ?.read<String>('value');

  Future<void> _setState(String key, String value) => db.customStatement(
    'INSERT INTO ledgy_local_state(key,value) VALUES (?,?) '
    'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );

  @override
  Future<void> prepare(
    String userId,
    String project, {
    required bool hasRemoteData,
  }) => db.transaction(() async {
    final owner = await _state('sync:owner');
    final ownerProject = await _state('sync:project');
    if (owner != null && (owner != userId || ownerProject != project)) {
      throw const SyncFailure(
        'Data perangkat ini tertaut ke akun atau proyek lain. '
        'Masuk kembali dengan akun yang sebelumnya untuk melanjutkan sinkronisasi.',
      );
    }
    if (owner != null) return;
    // A fresh install must download the existing ledger, not upload random-ID
    // starter rows and create a second Tunai / duplicate default categories.
    final pristine = hasRemoteData && await _isPristineStarter();
    if (pristine) {
      for (final table in SyncTable.values.reversed) {
        await db.customUpdate(
          'DELETE FROM "${table.sqlName}"',
          updates: {_table(table)},
        );
      }
      await db.customStatement('DELETE FROM ledgy_sync_rows');
    } else {
      // Legacy seeds have is_dirty=false but have never been sent. Upload them
      // too, so all foreign-key parents exist before sending local transactions.
      for (final table in SyncTable.values) {
        await db.customUpdate(
          'UPDATE "${table.sqlName}" SET is_dirty=1',
          updates: {_table(table)},
        );
      }
    }
    await _setState('sync:owner', userId);
    await _setState('sync:project', project);
  });

  Future<bool> _isPristineStarter() async {
    for (final table in [
      SyncTable.transactions,
      SyncTable.budgets,
      SyncTable.recurringRules,
    ]) {
      if ((await db.select(_table(table)).get()).isNotEmpty) return false;
    }
    final accounts = await db.select(db.accounts).get();
    if (accounts.length > 1 ||
        accounts.any(
          (a) =>
              a.name != 'Tunai' ||
              a.initialBalance != 0 ||
              a.isDirty ||
              a.deletedAt != null,
        )) {
      return false;
    }
    const starter = {
      'Makan & Minum',
      'Transport',
      'Belanja',
      'Tagihan',
      'Hiburan',
      'Kesehatan',
      'Gaji',
      'Lainnya',
    };
    final categories = await db.select(db.categories).get();
    return categories.length <= starter.length &&
        categories.every(
          (c) =>
              starter.contains(c.name) &&
              !c.isDirty &&
              c.deletedAt == null &&
              c.kind == (c.name == 'Gaji' ? 'income' : 'expense'),
        );
  }

  @override
  Future<List<SyncRecord>> dirty(SyncTable table) async {
    final rows = await db
        .customSelect(
          'SELECT t.*, COALESCE(s.revision,0) AS sync_revision '
          'FROM "${table.sqlName}" t LEFT JOIN ledgy_sync_rows s '
          'ON s.table_name=? AND s.row_id=t.id WHERE t.is_dirty=1 ORDER BY t.id',
          variables: [Variable(table.sqlName)],
          readsFrom: {_table(table)},
        )
        .get();
    return [
      for (final row in rows)
        SyncRecord(
          table,
          _wire(table, row.data),
          row.read<int>('sync_revision'),
        ),
    ];
  }

  Map<String, dynamic> _wire(SyncTable table, Map<String, dynamic> raw) => {
    for (final key in table.columns)
      key: SyncTable.dates.contains(key)
          ? raw[key] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    (raw[key] as int) * 1000,
                    isUtc: true,
                  ).toIso8601String()
          : (key == 'is_dirty' || key == 'is_active')
          ? raw[key] == 1
          : raw[key],
  };

  Future<QueryRow?> _metadata(SyncTable table, String id) => db
      .customSelect(
        'SELECT revision, server_updated_at FROM ledgy_sync_rows '
        'WHERE table_name=? AND row_id=?',
        variables: [Variable(table.sqlName), Variable(id)],
      )
      .getSingleOrNull();

  Future<void> _remember(SyncTable table, String id, DateTime version) =>
      db.customStatement(
        'INSERT INTO ledgy_sync_rows(table_name,row_id,server_updated_at) VALUES (?,?,?) '
        'ON CONFLICT(table_name,row_id) DO UPDATE SET server_updated_at=excluded.server_updated_at',
        [table.sqlName, id, version.toUtc().toIso8601String()],
      );

  DateTime? _version(QueryRow? metadata) {
    final stamp = metadata?.readNullable<String>('server_updated_at');
    return stamp == null ? null : DateTime.parse(stamp).toUtc();
  }

  @override
  Future<void> acknowledge(
    SyncRecord sent,
    Map<String, dynamic> returned,
  ) => db.transaction(() async {
    final metadata = await _metadata(sent.table, sent.id);
    final serverVersion = DateTime.parse(returned['updated_at'] as String)
        .toUtc();
    final previous = _version(metadata);
    if (previous != null && serverVersion.isBefore(previous)) return;
    // Read inside the same SQLite transaction as the write. A same-second edit
    // is distinguished by revision, rather than the truncated device timestamp.
    final current = await db
        .customSelect(
          'SELECT is_dirty FROM "${sent.table.sqlName}" WHERE id=?',
          variables: [Variable(sent.id)],
        )
        .getSingleOrNull();
    if (current == null) return;
    if (metadata?.read<int>('revision') == sent.revision) {
      await _write(sent.table, returned);
    }
    await _remember(sent.table, sent.id, serverVersion);
  });

  @override
  Future<void> merge(SyncTable table, List<Map<String, dynamic>> rows) =>
      db.transaction(() async {
        for (final row in rows) {
          final id = row['id'] as String;
          final current = await db
              .customSelect(
                'SELECT is_dirty FROM "${table.sqlName}" WHERE id=?',
                variables: [Variable(id)],
              )
              .getSingleOrNull();
          // Pending edits will receive their server timestamp on the next push.
          if (current?.read<int>('is_dirty') == 1) continue;
          final serverVersion = DateTime.parse(row['updated_at'] as String)
              .toUtc();
          final previous = _version(await _metadata(table, id));
          if (previous != null && !serverVersion.isAfter(previous)) continue;
          await _write(table, row);
          await _remember(table, id, serverVersion);
        }
      });

  Future<void> _write(SyncTable table, Map<String, dynamic> remote) async {
    final columns = table.columns;
    final marks = List.filled(columns.length, '?').join(',');
    final assignments = columns
        .where((key) => key != 'id')
        .map((key) => '"$key"=excluded."$key"')
        .join(',');
    await db.customUpdate(
      'INSERT INTO "${table.sqlName}" (${columns.map((k) => '"$k"').join(',')}) '
      'VALUES ($marks) ON CONFLICT(id) DO UPDATE SET $assignments',
      variables: [for (final key in columns) _variable(key, remote[key])],
      updates: {_table(table)},
    );
  }

  Variable _variable(String key, dynamic value) {
    if (key == 'is_dirty') return const Variable(false);
    if (SyncTable.dates.contains(key)) {
      return Variable<DateTime>(
        value == null ? null : DateTime.parse(value as String).toUtc(),
      );
    }
    if (key == 'is_active') return Variable<bool>(value as bool);
    if (key == 'initial_balance' || key == 'amount' || key == 'interval') {
      return Variable<int>(value as int);
    }
    return Variable<String>(value as String?);
  }

  Future<DateTime?> _dateState(String key) async {
    final value = await _state(key);
    return value == null ? null : DateTime.parse(value).toUtc();
  }

  @override
  Future<DateTime?> cursor() => _dateState('sync:last_synced_at');
  @override
  Future<DateTime?> lastSuccess() => _dateState('sync:last_success_at');

  @override
  Future<void> complete(DateTime serverTime) => db.transaction(() async {
    await db.normalizeLegacyCategories();
    final previous = await cursor();
    // A short overlap rereads equal boundary timestamps and recently committed
    // writes. Keyset pagination handles every row sharing an updated_at value.
    final next = serverTime.toUtc().subtract(const Duration(seconds: 2));
    if (previous == null || next.isAfter(previous)) {
      await _setState('sync:last_synced_at', next.toIso8601String());
    }
    await _setState(
      'sync:last_success_at',
      serverTime.toUtc().toIso8601String(),
    );
  });

  Selectable<QueryRow> _queueQuery() {
    final parts = [
      for (final table in SyncTable.values)
        'SELECT t.is_dirty, COALESCE(s.revision,0) AS revision '
            'FROM "${table.sqlName}" t LEFT JOIN ledgy_sync_rows s '
            "ON s.table_name='${table.sqlName}' AND s.row_id=t.id",
    ];
    return db.customSelect(
      'SELECT COALESCE(SUM(is_dirty),0) AS pending, '
      'COALESCE(SUM(revision),0) AS revision FROM (${parts.join(' UNION ALL ')})',
      readsFrom: {for (final table in SyncTable.values) _table(table)},
    );
  }

  SyncQueue _queue(QueryRow row) =>
      SyncQueue(row.read<int>('pending'), row.read<int>('revision'));
  @override
  Future<SyncQueue> queue() async => _queue(await _queueQuery().getSingle());
  @override
  Stream<SyncQueue> watchQueue() =>
      _queueQuery().watchSingle().map(_queue).distinct((a, b) => a.sameAs(b));
}
