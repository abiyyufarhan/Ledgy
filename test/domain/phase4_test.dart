import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/features/budgets/domain/usecases/budget_alert_policy.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/recurring/domain/usecases/recurring_schedule.dart';
import 'package:ledgy/features/reports/domain/finance_report.dart';
import 'package:ledgy/features/transactions/domain/entities/transaction.dart';
import 'package:ledgy/features/transfer/data/csv_repository.dart';
import 'package:ledgy/features/transfer/domain/ledger_csv.dart';

void main() {
  group('Peringatan anggaran', () {
    test('ambang 80 dan 100, termasuk melewati batas langsung', () {
      expect(BudgetAlertPolicy.nextThreshold(budgeted: 100, spent: 79), isNull);
      expect(BudgetAlertPolicy.nextThreshold(budgeted: 100, spent: 80), 80);
      expect(
        BudgetAlertPolicy.nextThreshold(budgeted: 100, spent: 99, sent: {80}),
        isNull,
      );
      expect(
        BudgetAlertPolicy.nextThreshold(budgeted: 100, spent: 100, sent: {80}),
        100,
      );
      expect(BudgetAlertPolicy.nextThreshold(budgeted: 100, spent: 125), 100);
      expect(
        BudgetAlertPolicy.nextThreshold(budgeted: 100, spent: 125, sent: {100}),
        isNull,
      );
      expect(BudgetAlertPolicy.nextThreshold(budgeted: 0, spent: 100), isNull);
    });
    test(
      'kategori induk menjumlah seluruh aset dan subkategori tanpa transfer',
      () {
        final now = DateTime(2026, 10, 1, 22, 30);
        LedgerTransaction t(
          String id,
          String category,
          int amount, {
          String account = 'jago',
          TransactionType type = TransactionType.expense,
          DateTime? deleted,
        }) => LedgerTransaction(
          id: id,
          type: type,
          amount: amount,
          accountId: account,
          categoryId: category,
          occurredAt: now,
          deletedAt: deleted,
        );
        final items = [
          t('1', 'cafe', 40),
          t('2', 'food', 40, account: 'cash'),
          t('3', 'cafe', 500, type: TransactionType.transfer),
          t('4', 'cafe', 100, deleted: now),
        ];
        expect(
          FinanceReports.budgetSpent(
            category: 'Makan & Minum',
            month: now,
            items: items,
            categoryNames: {
              'cafe': 'Makanan & Minuman • Cafe /Warkop',
              'food': 'Makanan',
            },
          ),
          80,
        );
        expect(FinanceReports.month(items, now).expense, 80);
      },
    );
  });
  group('Jadwal berulang', () {
    test('tanggal 31 kembali ke 31 setelah Februari', () {
      final due = RecurringSchedule.due(
        next: DateTime.utc(2026, 1, 31, 22, 30),
        now: DateTime.utc(2026, 3, 31, 22, 30),
        frequency: 'monthly',
        interval: 1,
      );
      expect(due.dates, [
        DateTime.utc(2026, 1, 31, 22, 30),
        DateTime.utc(2026, 2, 28, 22, 30),
        DateTime.utc(2026, 3, 31, 22, 30),
      ]);
      expect(due.next, DateTime.utc(2026, 4, 30, 22, 30));
    });
    test('tahun kabisat, interval dan batas tanggal jatuh tempo', () {
      expect(
        RecurringSchedule.advance(DateTime.utc(2024, 1, 31), 'monthly', 1, 31),
        DateTime.utc(2024, 2, 29),
      );
      expect(
        RecurringSchedule.due(
          next: DateTime.utc(2026, 1, 1),
          now: DateTime.utc(2025, 12, 31),
          frequency: 'monthly',
          interval: 1,
        ).dates,
        isEmpty,
      );
      final due = RecurringSchedule.due(
        next: DateTime.utc(2026, 1, 1, 9),
        now: DateTime.utc(2026, 1, 29, 9),
        frequency: 'weekly',
        interval: 2,
      );
      expect(due.dates.length, 3);
      expect(due.next, DateTime.utc(2026, 2, 12, 9));
      expect(
        () => RecurringSchedule.due(
          next: DateTime.now(),
          now: DateTime.now(),
          frequency: 'daily',
          interval: 0,
        ),
        throwsArgumentError,
      );
    });
    test('harian melewati pergantian bulan dengan jam sama', () {
      final due = RecurringSchedule.due(
        next: DateTime(2026, 9, 30, 22, 30),
        now: DateTime(2026, 10, 2, 22, 30),
        frequency: 'daily',
        interval: 1,
      );
      expect(due.dates.length, 3);
      expect(due.next, DateTime(2026, 10, 3, 22, 30));
    });
  });

  group('Persistensi lokal', () {
    late AppDatabase db;
    late LocalFinanceRepository finance;
    late Account account;
    late String expenseCategory;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      finance = LocalFinanceRepository(db);
      account = (await finance.snapshot()).accounts.first;
      expenseCategory = await finance.ensureCategory(
        'Makan & Minum • Cafe / Warkop',
        'expense',
      );
    });
    tearDown(() async => db.close());
    Future<void> expense(int amount, DateTime date) async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'expense-$amount-${date.toIso8601String()}',
              type: 'expense',
              amount: amount,
              accountId: account.id,
              categoryId: Value(expenseCategory),
              occurredAt: date.toUtc(),
              createdAt: date.toUtc(),
              updatedAt: date.toUtc(),
            ),
          );
    }

    test('peringatan tersimpan, tidak diulang, 100% setelah 80%', () async {
      final now = DateTime(2026, 10, 1, 12);
      await finance.saveBudget('Makan & Minum', 100, now);
      await expense(80, now);
      final sent = <int>[];
      Future<bool> notify(BudgetProgress p, int threshold) async {
        sent.add(threshold);
        return true;
      }

      await finance.checkBudgets(now, notify);
      await LocalFinanceRepository(db).checkBudgets(now, notify);
      expect(sent, [80]);
      await expense(20, now);
      await finance.checkBudgets(now, notify);
      await finance.checkBudgets(now, notify);
      expect(sent, [80, 100]);
      await finance.saveBudget('Makan & Minum', 100, DateTime(2026, 11));
      await expense(100, DateTime(2026, 11, 1));
      await finance.checkBudgets(DateTime(2026, 11, 1), notify);
      expect(sent, [80, 100, 100]);
    });
    test('izin ditolak tidak menghabiskan peringatan', () async {
      final now = DateTime(2026, 10, 1);
      await finance.saveBudget('Makan & Minum', 100, now);
      await expense(85, now);
      await finance.checkBudgets(now, (p, t) async => false);
      var calls = 0;
      await finance.checkBudgets(now, (p, t) async {
        calls++;
        return true;
      });
      expect(calls, 1);
    });
    test('generasi idempotent, catchup, jeda dan soft-delete', () async {
      final start = DateTime(2026, 1, 31, 22, 30);
      await finance.saveRule(
        type: 'expense',
        amount: 50,
        accountId: account.id,
        categoryId: expenseCategory,
        note: 'Tagihan',
        frequency: 'monthly',
        interval: 1,
        next: start,
      );
      expect(await finance.generateDue(DateTime(2026, 3, 31, 22, 30)), 3);
      expect(
        await LocalFinanceRepository(db)
            .generateDue(DateTime(2026, 3, 31, 22, 30)),
        0,
      );
      var s = await finance.snapshot();
      expect(s.transactions.length, 3);
      expect(
        s.rules.single.nextOccurrenceAt.toLocal(),
        DateTime(2026, 4, 30, 22, 30),
      );
      await db.transactionsDao.softDelete(
        s.transactions.first.id,
        DateTime.now(),
      );
      expect(await finance.generateDue(DateTime(2026, 3, 31, 22, 30)), 0);
      await finance.toggleRule(s.rules.single.id, false);
      expect(await finance.generateDue(DateTime(2026, 5, 31, 22, 30)), 0);
      await finance.toggleRule(s.rules.single.id, true);
      expect(await finance.generateDue(DateTime(2026, 5, 31, 22, 30)), 2);
      s = await finance.snapshot();
      expect(s.transactions.length, 5);
    });
    test('aset diarsipkan tidak menghasilkan transaksi otomatis', () async {
      await finance.saveRule(
        type: 'expense',
        amount: 50,
        accountId: account.id,
        categoryId: expenseCategory,
        frequency: 'daily',
        interval: 1,
        next: DateTime(2026, 1, 1),
      );
      await db.accountsDao.softDelete(account.id, DateTime.now());
      expect(await finance.generateDue(DateTime(2026, 1, 2)), 0);
    });
    test(
      'kegagalan generasi membatalkan transaksi dan kemajuan jadwal',
      () async {
        final start = DateTime(2026, 1, 1);
        await finance.saveRule(
          type: 'expense',
          amount: 50,
          accountId: account.id,
          categoryId: expenseCategory,
          frequency: 'daily',
          interval: 1,
          next: start,
        );
        await db.customStatement(
          'CREATE TRIGGER fail_second BEFORE INSERT ON transactions '
          'WHEN (SELECT COUNT(*) FROM transactions) >= 1 '
          "BEGIN SELECT RAISE(ABORT, 'test rollback'); END",
        );
        await expectLater(
          finance.generateDue(DateTime(2026, 1, 3)),
          throwsA(anything),
        );
        final failed = await finance.snapshot();
        expect(failed.transactions, isEmpty);
        expect(failed.rules.single.nextOccurrenceAt.toLocal(), start);
        await db.customStatement('DROP TRIGGER fail_second');
        expect(await finance.generateDue(DateTime(2026, 1, 3)), 3);
        expect(await finance.generateDue(DateTime(2026, 1, 3)), 0);
      },
    );
    test('dua pemrosesan bersamaan tidak menggandakan transaksi', () async {
      await finance.saveRule(
        type: 'expense',
        amount: 50,
        accountId: account.id,
        categoryId: expenseCategory,
        frequency: 'daily',
        interval: 1,
        next: DateTime(2026, 1, 1),
      );
      final counts = await Future.wait([
        finance.generateDue(DateTime(2026, 1, 3)),
        LocalFinanceRepository(db).generateDue(DateTime(2026, 1, 3)),
      ]);
      expect(counts.reduce((a, b) => a + b), 3);
      expect((await finance.snapshot()).transactions.length, 3);
    });
    test(
      'ekspor-impor: pratinjau, duplikat dan tidak menulis sebelum konfirmasi',
      () async {
        await expense(100, DateTime(2026, 10, 1, 22, 30));
        final csv = CsvRepository(finance);
        final exported = await csv.export();
        expect(
          (await csv.preview(exported)).single.status,
          ImportStatus.duplicate,
        );
        expect(await csv.import(exported), 0);
        final content = LedgerCsv.encode([
          LedgerCsv.headers,
          [
            '',
            'expense',
            '500',
            '',
            account.name,
            '',
            '',
            '',
            'Makanan & Minuman • Cafe /Warkop',
            'Kopi, "sore"\nbersama',
            DateTime.utc(2026, 10, 2, 15, 30).toIso8601String(),
          ],
        ]);
        final before = (await finance.snapshot()).transactions.length;
        expect((await csv.preview(content)).single.status, ImportStatus.ready);
        expect((await finance.snapshot()).transactions.length, before);
        expect(await csv.import(content), 1);
        expect(await csv.import(content), 0);
        final latest = (await finance.snapshot()).transactions.last;
        expect(latest.note, 'Kopi, "sore"\nbersama');
      },
    );
    test(
      'ekspor CSV terpilih tidak menyertakan transaksi di luar filter',
      () async {
        await expense(100, DateTime(2026, 10, 1));
        await expense(200, DateTime(2026, 9, 1));
        final csv = CsvRepository(finance);
        final selected = (await finance.snapshot()).transactions.first.id;
        final rows = LedgerCsv.decode(
          await csv.export(transactionIds: {selected}),
        );
        expect(rows.single['id'], selected);
        expect(LedgerCsv.decode(await csv.export()), hasLength(2));
        expect(LedgerCsv.decode(await csv.export(transactionIds: {})), isEmpty);
      },
    );

    test('duplikat antarbaris, nominal invalid dan aset asing', () async {
      final row = [
        '',
        'expense',
        '500',
        '',
        account.name,
        '',
        '',
        '',
        'Tagihan',
        'Listrik',
        '2026-10-01T12:00:00Z',
      ];
      final bad = [...row];
      bad[2] = '-5';
      final foreign = [...row];
      foreign[4] = 'Tidak Ada';
      final content = LedgerCsv.encode([
        LedgerCsv.headers,
        row,
        row,
        bad,
        foreign,
      ]);
      final preview = await CsvRepository(finance).preview(content);
      expect(preview.map((r) => r.status), [
        ImportStatus.ready,
        ImportStatus.duplicate,
        ImportStatus.invalid,
        ImportStatus.invalid,
      ]);
      expect(await CsvRepository(finance).import(content), 1);
    });
  });
  test('CSV roundtrip, formula aman, kutip salah ditolak', () {
    final rows = [
      LedgerCsv.headers,
      [
        'x',
        'expense',
        '100',
        'cash',
        'Tunai',
        '',
        '',
        '',
        'Tagihan',
        LedgerCsv.safeText('=HYPERLINK("test")'),
        '2026-10-01T12:00:00Z',
      ],
    ];
    final decoded = LedgerCsv.decode(LedgerCsv.encode(rows));
    expect(
      LedgerCsv.originalText(decoded.single['note']!),
      '=HYPERLINK("test")',
    );
    expect(
      () => LedgerCsv.decode('type,amount,occurred_at\n"expense,100,2026'),
      throwsFormatException,
    );
  });
  test('tanggal CSV tidak boleh overflow atau tanpa zona waktu', () {
    expect(LedgerCsv.parseDate('2026-02-30T12:30:00Z'), isNull);
    expect(LedgerCsv.parseDate('2026-01-01T24:30:00Z'), isNull);
    expect(LedgerCsv.parseDate('2026-01-01T12:30:00'), isNull);
    expect(
      LedgerCsv.parseDate('2024-02-29T22:30:00+07:00'),
      DateTime.utc(2024, 2, 29, 15, 30),
    );
  });
  test('laporan enam bulan lintas tahun dan cashflow mengabaikan transfer', () {
    LedgerTransaction item(
      String id,
      DateTime date,
      TransactionType type,
      int amount,
    ) => LedgerTransaction(
      id: id,
      occurredAt: date,
      type: type,
      amount: amount,
      accountId: 'cash',
      categoryId: 'bills',
    );
    final items = [
      item('old', DateTime(2025, 7), TransactionType.expense, 500),
      item('salary', DateTime(2026, 1, 1, 0, 1), TransactionType.income, 1000),
      item('bill', DateTime(2026, 1, 31, 23, 59), TransactionType.expense, 200),
      item('transfer', DateTime(2026, 1), TransactionType.transfer, 5000),
      item('future', DateTime(2026, 2), TransactionType.expense, 100),
    ];
    final report = FinanceReports.sixMonths(items, DateTime(2026, 1));
    expect(report.length, 6);
    expect(report.first.month, DateTime(2025, 8));
    expect(report.last.net, 800);
    expect(
      FinanceReports.categoryTotals(items, DateTime(2026, 1), {
        'bills': 'Tagihan',
      }),
      {'Tagihan': 200},
    );
  });
}
