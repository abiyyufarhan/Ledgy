import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/features/categories/domain/category_catalog.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/reports/data/finance_report_exporter.dart';
import 'package:ledgy/features/sync/data/sqlite_sync_store.dart';
import 'package:ledgy/features/sync/domain/sync_models.dart';
import 'package:ledgy/features/transactions/data/repositories/transactions_repository_impl.dart';
import 'package:ledgy/features/transactions/domain/transaction_period.dart';
import 'package:ledgy/features/transactions/domain/usecases/calculate_account_balance.dart';
import 'package:ledgy/features/transfer/data/csv_repository.dart';
import 'package:ledgy/features/transfer/domain/ledger_csv.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('katalog pemasukan sesuai urutan dan tetap memuat Gaji lama', () {
    expect(incomeCategoryGroups.keys, [
      'Acara Sosial',
      'Pemasukan',
      'Pencairan Pinjaman',
      'Tabungan',
      'Lainnya',
    ]);
    expect(incomeCategoryGroups.values.expand((children) => children), [
      'Amal & Donasi',
      'Hadiah',
      'Bonus',
      'Gaji',
      'Laba Atas Investasi',
      'Laba Usaha',
      'Pendapatan Tambahan',
      'Tunjangan / Uang Saku',
      'Uang Masuk',
      'Investasi',
      'Bunga',
      'Cashback',
      'Pelunasan',
      'Penggantian Biaya',
      'Refund',
    ]);
    expect(incomeCategoryName('Gaji'), 'Pemasukan • Gaji');
    expect(incomeCategoryName('Pendapatan Pribadi'), 'Pendapatan Pribadi');
  });

  test('migrasi v1 mempertahankan transaksi dan penerima bertahan setelah dibuka ulang', () async {
    final folder = await Directory.systemTemp.createTemp(
      'ledgy-recipient-test-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/ledger.sqlite');
    final old = AppDatabase(NativeDatabase(file));
    final account = (await old.accountsDao.watchActive().first).first;
    final date = DateTime.utc(2026, 10, 7);
    await old.transactionsDao.save(
      TransactionsCompanion.insert(
        id: 'legacy',
        type: 'transfer',
        amount: 100,
        accountId: account.id,
        toAccountId: Value('legacy-target'),
        note: const Value('Riwayat lama'),
        occurredAt: date,
        createdAt: date,
        updatedAt: date,
      ),
    );
    // Reconstruct the exact v1 transaction columns and schema version.
    await old.customStatement(
      'ALTER TABLE transactions DROP COLUMN recipient_name',
    );
    await old.customStatement(
      'ALTER TABLE transactions DROP COLUMN recipient_account',
    );
    await old.customStatement('PRAGMA user_version = 1');
    await old.customStatement('DROP TABLE quick_input_memory');
    await old.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final legacy = await migrated.transactionsDao.watchActive().first;
    expect(legacy.single.note, 'Riwayat lama');
    expect(legacy.single.toAccountId, 'legacy-target');
    expect(legacy.single.recipientName, isNull);
    await TransactionActions(TransactionsRepository(migrated.transactionsDao))
        .save(
          id: 'external',
          type: 'transfer',
          amount: 25000,
          accountId: account.id,
          recipientName: 'Budi',
          recipientAccount: '0012345678',
          occurredAt: date,
        );
    await migrated.close();

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final rows = await reopened.transactionsDao.watchActive().first;
    final external = rows.firstWhere((t) => t.id == 'external');
    expect(external.recipientName, 'Budi');
    expect(external.recipientAccount, '0012345678');
    expect(rows, hasLength(2));
  });

  test('transfer eksternal tersimpan, diekspor, diimpor dan dikirim ke antrean sinkron', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final finance = LocalFinanceRepository(db);
    final account = (await finance.snapshot()).accounts.first;
    final date = DateTime.utc(2026, 10, 7, 14, 45);
    await TransactionActions(TransactionsRepository(db.transactionsDao)).save(
      id: 'external',
      type: 'transfer',
      amount: 25000,
      accountId: account.id,
      recipientName: 'Budi',
      recipientAccount: '0012345678',
      note: 'Catatan transfer',
      occurredAt: date,
    );
    final snapshot = await finance.snapshot();
    expect(
      AccountBalanceCalculator.calculate(
        accountId: account.id,
        initialBalance: 100000,
        transactions: snapshot.ledger,
      ).balance,
      75000,
    );
    final queue = await SqliteSyncStore(db).dirty(SyncTable.transactions);
    expect(queue.single.data['recipient_name'], 'Budi');
    expect(queue.single.data['recipient_account'], '0012345678');

    final csv = CsvRepository(finance);
    final exported = await csv.export();
    expect(
      LedgerCsv.decode(exported).single['recipient_account'],
      '0012345678',
    );
    expect((await csv.preview(exported)).single.status, ImportStatus.duplicate);
    await db.delete(db.transactions).go();
    expect((await csv.preview(exported)).single.status, ImportStatus.ready);
    expect(await csv.import(exported), 1);
    final restored = (await finance.snapshot()).transactions.single;
    expect(restored.recipientName, 'Budi');
    expect(restored.recipientAccount, '0012345678');
    expect(restored.note, 'Catatan transfer');

    final report = TransactionReport(
      transactions: [restored],
      accounts: snapshot.accounts,
      categories: snapshot.categories,
      date: date.toLocal(),
      period: TransactionPeriod.monthly,
    );
    final bytes = await FinanceReportExporter.encode(
      report,
      FinanceReportFormat.xlsx,
    );
    final book = xlsx.Excel.decodeBytes(bytes);
    expect(
      book['Transaksi'].rows[1][3]!.value,
      xlsx.TextCellValue('Budi • 0012345678'),
    );
    expect(report.income, 0);
    expect(report.expense, 0);
  });
}
