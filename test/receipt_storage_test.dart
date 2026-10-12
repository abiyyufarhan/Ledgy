import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/features/local/data/local_finance_repository.dart';
import 'package:ledgy/features/quick_input/data/receipt_storage.dart';
import 'package:ledgy/features/quick_input/data/quick_input_actions.dart';
import 'package:ledgy/features/quick_input/data/sqlite_quick_input_memory_repository.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';
import 'package:ledgy/features/transactions/data/repositories/transactions_repository_impl.dart';

class FailingRepository extends TransactionsRepository {
  FailingRepository(super.dao);
  @override
  Future<void> save(TransactionsCompanion value) async =>
      throw StateError('simulated failure');
}

void main() {
  late AppDatabase db;
  late Directory root, attachments;
  late File original;
  late ReceiptStorage storage;
  late TransactionDraft draft;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('ledgy-receipt-test-');
    attachments = await Directory('${root.path}/attachments').create();
    original = await File('${root.path}/gallery-original.jpg')
        .writeAsBytes([1, 2, 3]);
    storage = ReceiptStorage(
      LocalFinanceRepository(db),
      directory: () async => attachments,
    );
    final account = (await db.accountsDao.watchActive().first).first;
    final category = (await db.categoriesDao.watchActive().first).firstWhere(
      (c) => c.kind == 'expense',
    );
    draft = TransactionDraft(
      type: TransactionType.expense,
      amount: 35000,
      accountId: account.id,
      categoryId: category.id,
      occurredAt: DateTime.now().toUtc(),
      source: DraftSource.receipt,
      receiptPhotoPath: original.path,
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  QuickInputActions actions({bool fail = false}) => QuickInputActions(
    db,
    TransactionActions(
      fail
          ? FailingRepository(db.transactionsDao)
          : TransactionsRepository(db.transactionsDao),
    ),
    SqliteQuickInputMemoryRepository(db),
    receipts: storage,
  );
  test(
    'default off saves ledger only and preserves gallery original',
    () async {
      expect(await storage.enabled(), isFalse);
      final saved = await actions().save(original: draft, corrected: draft);
      final transaction = (await db.select(db.transactions).get()).single;
      expect(transaction.amount, 35000);
      expect(saved.receiptPhotoPath, isNull);
      expect(await storage.photoFor(transaction.id), isNull);
      expect(await attachments.list().toList(), isEmpty);
      expect(await original.exists(), isTrue);
    },
  );
  test('opt in links a local copy to repository transaction; reset deletes attachments only', () async {
    await storage.setEnabled(true);
    await actions().save(original: draft, corrected: draft);
    final transaction = (await db.select(db.transactions).get()).single;
    final file = await storage.photoFor(transaction.id);
    expect(file, isNotNull);
    expect(file, isNot(original.path));
    expect(await File(file!).readAsBytes(), [1, 2, 3]);
    expect(transaction.note, isNull);
    await storage.clearAttachments();
    expect(await File(file).exists(), isFalse);
    expect(await storage.photoFor(transaction.id), isNull);
    expect(await original.exists(), isTrue);
  });
  test(
    'failed repository save rolls back attachment metadata and staged copy',
    () async {
      await storage.setEnabled(true);
      await expectLater(
        actions(fail: true).save(original: draft, corrected: draft),
        throwsStateError,
      );
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await attachments.list().toList(), isEmpty);
      expect(await original.exists(), isTrue);
    },
  );
}
