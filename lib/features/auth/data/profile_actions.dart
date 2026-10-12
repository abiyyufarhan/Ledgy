import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local/data/local_finance_repository.dart';
import '../../local/presentation/local_providers.dart';
import '../../sync/domain/sync_service.dart';
import '../../sync/presentation/sync_providers.dart';
import '../domain/auth_repository.dart';
import '../domain/account_profile_repository.dart';
import '../../quick_input/data/receipt_storage.dart';
import '../../quick_input/presentation/receipt_providers.dart';

final profileActionsProvider = Provider(
  (ref) => ProfileActions(
    ref.watch(authRepositoryProvider),
    ref.watch(localFinanceProvider),
    ref.watch(syncServiceProvider),
    receipts: ref.watch(receiptStorageProvider),
  ),
);

class ProfileActions {
  ProfileActions(this.auth, this.finance, this.sync, {this.receipts});
  final AuthRepository auth;
  final LocalFinanceRepository finance;
  final SyncService sync;
  final ReceiptStorage? receipts;

  List<TableInfo> get _tables => [
    finance.db.recurringRules,
    finance.db.budgets,
    finance.db.transactions,
    finance.db.categories,
    finance.db.accounts,
  ];

  Future<void> _checkOwner() async {
    final owner = await finance.state('sync:owner');
    if (auth.currentUser != null &&
        owner != null &&
        owner != auth.currentUser!.id) {
      throw const AuthFailure(
        'Data perangkat tertaut ke akun lain. Masuk dengan akun pemilik data terlebih dahulu.',
      );
    }
  }

  Future<void> _clearLedgerState() => finance.db.customStatement(
    "DELETE FROM ledgy_local_state WHERE key LIKE 'csv:%' OR key LIKE 'budget:%' "
    "OR key LIKE 'anchor:%' OR key LIKE 'recurring:%' OR key LIKE 'occurrence:%' "
    "OR key LIKE 'parser:%' OR key='dashboard:savings-goals:v1'",
  );

  /// Keep deletion markers so offline resets also reach the owning cloud ledger.
  Future<void> resetData() => sync.withMaintenance(() async {
    await _checkOwner();
    await receipts?.clearAttachments();
    final db = finance.db;
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      for (final table in _tables) {
        await db.customUpdate(
          'UPDATE "${table.actualTableName}" SET deleted_at=?, updated_at=?, is_dirty=1 WHERE deleted_at IS NULL',
          variables: [Variable(now), Variable(now)],
          updates: {table},
        );
      }
      await _clearLedgerState();
      await db.delete(db.quickInputMemory).go();
      await db.customStatement('DELETE FROM parser_failures');
      await finance.setState('dashboard:savings-goals:v1', '[]');
      await db.seedDefaults();
      for (final table in <TableInfo>[db.accounts, db.categories]) {
        await db.customUpdate(
          'UPDATE "${table.actualTableName}" SET is_dirty=1 WHERE deleted_at IS NULL',
          updates: {table},
        );
      }
    });
  });

  /// Cloud deletion must succeed before any local data is removed.
  Future<void> deleteAccount() => sync.withMaintenance(() async {
    final repository = auth;
    if (repository.currentUser == null) {
      throw const AuthFailure('Masuk terlebih dahulu.');
    }
    if (repository is! AccountProfileRepository) {
      throw const AuthFailure('Penghapusan akun belum tersedia.');
    }
    await _checkOwner();
    await (repository as AccountProfileRepository).deleteAccount();
    await receipts?.clearAttachments();
    final db = finance.db;
    await db.transaction(() async {
      for (final table in _tables) {
        await db.customUpdate(
          'DELETE FROM "${table.actualTableName}"',
          updates: {table},
        );
      }
      await db.customStatement('DELETE FROM ledgy_sync_rows');
      await db.delete(db.quickInputMemory).go();
      await db.customStatement('DELETE FROM parser_failures');
      await _clearLedgerState();
      await db.customStatement(
        "DELETE FROM ledgy_local_state WHERE key LIKE 'sync:%'",
      );
      await db.seedDefaults();
    });
  });
}
