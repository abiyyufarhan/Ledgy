import 'package:ledgy/features/sync/domain/sync_models.dart';

const syncUser = '11111111-1111-4111-8111-111111111111';
const otherSyncUser = '22222222-2222-4222-8222-222222222222';
const walletId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const categoryId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const transactionId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const budgetId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const ruleId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

/// Models the phase-5 owner/FK constraints and server timestamp trigger. Every
/// push is an upsert; the last accepted write wins regardless of device time.
class SyncTestServer implements SyncRemote {
  final rows = {
    for (final table in SyncTable.values)
      table: <String, Map<String, dynamic>>{},
  };
  DateTime clock = DateTime.utc(2026, 10, 2, 12);
  bool offline = false;
  SyncTable? failPull;
  SyncTable? failPush;
  Future<void> Function(SyncRecord)? beforePush;
  Future<void> Function(SyncRecord)? afterPush;
  final pushed = <SyncTable>[];
  int windowCalls = 0;
  int pullCalls = 0;
  void _online() {
    if (offline) throw const SyncOffline();
  }

  DateTime _tick() => clock = clock.add(const Duration(microseconds: 100));

  @override
  Future<SyncWindow> window(String userId) async {
    _online();
    windowCalls++;
    return SyncWindow(
      _tick(),
      hasData: rows.values.any(
        (table) => table.values.any((row) => row['user_id'] == userId),
      ),
    );
  }

  @override
  Future<Map<String, dynamic>> push(String userId, SyncRecord row) async {
    _online();
    await beforePush?.call(row);
    if (failPush == row.table) {
      throw const SyncFailure('Simulated rejected write');
    }
    final previous = rows[row.table]![row.id];
    if (previous != null && previous['user_id'] != userId) {
      throw const SyncFailure('Wrong owner');
    }
    for (final key in ['account_id', 'to_account_id', 'category_id']) {
      final id = row.data[key];
      if (id == null) continue;
      final parent =
          rows[key == 'category_id'
              ? SyncTable.categories
              : SyncTable.accounts]![id];
      if (parent == null || parent['user_id'] != userId) {
        throw const SyncFailure('Missing parent');
      }
    }
    final returned = {
      ...row.data,
      'user_id': userId,
      'is_dirty': false,
      'updated_at': _tick().toIso8601String(),
    };
    rows[row.table]![row.id] = returned;
    pushed.add(row.table);
    await afterPush?.call(row);
    return {...returned};
  }

  int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final stamp = DateTime.parse(a['updated_at'])
        .compareTo(DateTime.parse(b['updated_at']));
    return stamp != 0
        ? stamp
        : (a['id'] as String).compareTo(b['id'] as String);
  }

  @override
  Future<List<Map<String, dynamic>>> pull(
    String userId,
    SyncTable table, {
    DateTime? after,
    required DateTime through,
    Map<String, dynamic>? pageAfter,
    required int limit,
  }) async {
    _online();
    pullCalls++;
    if (failPull == table) {
      throw const SyncFailure('Simulated partial pull failure');
    }
    final selected = rows[table]!.values.where((row) {
      final stamp = DateTime.parse(row['updated_at'] as String);
      return row['user_id'] == userId &&
          (after == null || stamp.isAfter(after)) &&
          !stamp.isAfter(through) &&
          (pageAfter == null || _compare(row, pageAfter) > 0);
    }).toList()..sort(_compare);
    return selected
        .take(limit)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
