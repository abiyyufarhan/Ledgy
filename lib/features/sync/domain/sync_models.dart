enum SyncTable {
  accounts(['name', 'initial_balance']),
  categories(['name', 'kind']),
  transactions([
    'type',
    'amount',
    'account_id',
    'to_account_id',
    'recipient_name',
    'recipient_account',
    'category_id',
    'note',
    'occurred_at',
  ]),
  budgets(['category_id', 'amount', 'month_start']),
  recurringRules([
    'type',
    'amount',
    'account_id',
    'to_account_id',
    'category_id',
    'note',
    'frequency',
    'interval',
    'next_occurrence_at',
    'is_active',
  ]);

  const SyncTable(this.fields);
  final List<String> fields;
  String get sqlName => this == recurringRules ? 'recurring_rules' : name;
  List<String> get columns => [
    'id',
    ...fields,
    'created_at',
    'updated_at',
    'deleted_at',
    'is_dirty',
  ];
  static const dates = {
    'created_at',
    'updated_at',
    'deleted_at',
    'occurred_at',
    'month_start',
    'next_occurrence_at',
  };
}

class SyncRecord {
  SyncRecord(this.table, Map<String, dynamic> data, this.revision)
    : data = Map.unmodifiable(data);
  final SyncTable table;
  final Map<String, dynamic> data;
  final int revision;
  String get id => data['id'] as String;
}

class SyncWindow {
  const SyncWindow(this.serverTime, {required this.hasData});
  final DateTime serverTime;
  final bool hasData;
}

class SyncQueue {
  const SyncQueue(this.pending, this.revision);
  final int pending;
  final int revision;
  bool sameAs(SyncQueue other) =>
      pending == other.pending && revision == other.revision;
}

enum SyncPhase { local, waiting, syncing, synced, failed }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.local,
    this.pending = 0,
    this.lastSyncedAt,
    this.message = 'Masuk untuk menyinkronkan data antarperangkat.',
  });
  final SyncPhase phase;
  final int pending;
  final DateTime? lastSyncedAt;
  final String message;
  String get label => switch (phase) {
    SyncPhase.local => 'Mode lokal',
    SyncPhase.waiting => 'Menunggu',
    SyncPhase.syncing => 'Menyinkronkan',
    SyncPhase.synced => 'Tersinkron',
    SyncPhase.failed => 'Gagal',
  };
}

class SyncFailure implements Exception {
  const SyncFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class SyncOffline implements Exception {
  const SyncOffline();
}

class SyncSessionChanged implements Exception {
  const SyncSessionChanged();
}

abstract interface class SyncLocalStore {
  Future<void> prepare(
    String userId,
    String project, {
    required bool hasRemoteData,
  });
  Future<List<SyncRecord>> dirty(SyncTable table);
  Future<void> acknowledge(SyncRecord sent, Map<String, dynamic> returned);
  Future<void> merge(SyncTable table, List<Map<String, dynamic>> rows);
  Future<DateTime?> cursor();
  Future<DateTime?> lastSuccess();
  Future<void> complete(DateTime serverTime);
  Future<SyncQueue> queue();
  Stream<SyncQueue> watchQueue();
}

abstract interface class SyncRemote {
  Future<SyncWindow> window(String userId);
  Future<Map<String, dynamic>> push(String userId, SyncRecord row);
  Future<List<Map<String, dynamic>>> pull(
    String userId,
    SyncTable table, {
    DateTime? after,
    required DateTime through,
    Map<String, dynamic>? pageAfter,
    required int limit,
  });
}
