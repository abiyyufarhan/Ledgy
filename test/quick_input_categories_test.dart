import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/features/categories/data/repositories/categories_repository_impl.dart';
import 'package:ledgy/features/quick_input/data/quick_input_actions.dart';
import 'package:ledgy/features/quick_input/data/quick_input_categories.dart';
import 'package:ledgy/features/quick_input/data/sqlite_quick_input_memory_repository.dart';
import 'package:ledgy/features/quick_input/domain/quick_input_memory_repository.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_context.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';
import 'package:ledgy/features/quick_input/presentation/quick_input_providers.dart';
import 'package:ledgy/features/transactions/data/repositories/transactions_repository_impl.dart';

class _FailingMemory implements QuickInputMemoryRepository {
  @override
  Future<void> learn(
    TransactionDraft original,
    TransactionDraft corrected,
  ) async => throw StateError('rollback');
  @override
  Future<String?> lastAccountId() async => null;
  @override
  Future<List<KeywordMemory>> readAll() async => [];
  @override
  Stream<List<KeywordMemory>> watchAll() => Stream.value([]);
}

final _dateForTest = DateTime.utc(2026, 10, 8);

void main() {
  late AppDatabase db;
  late CategoriesRepository repository;
  late QuickInputCategories catalog;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = CategoriesRepository(db.categoriesDao);
    catalog = QuickInputCategories(repository);
  });
  tearDown(() => db.close());

  Future<TransactionDraft> draft() async {
    final categories = await repository.watchAll().first;
    final cafe = catalog.preview(categories).last;
    return TransactionDraft(
      type: TransactionType.expense,
      amount: 35000,
      accountId: (await db.accountsDao.watchActive().first).first.id,
      categoryId: cafe.id,
      occurredAt: DateTime.now().toUtc(),
      note: 'minum kopi',
    );
  }

  QuickInputActions actions({QuickInputMemoryRepository? memory}) =>
      QuickInputActions(
        db,
        TransactionActions(TransactionsRepository(db.transactionsDao)),
        memory ?? SqliteQuickInputMemoryRepository(db),
        categories: catalog,
      );

  test('preview has stable UUID and does not write any category', () async {
    final existing = await repository.watchAll().first;
    final first = catalog.preview(existing).last;
    expect(first.name, QuickInputCategories.cafeName);
    expect(
      first.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(catalog.preview(existing).last.id, first.id);
    expect(await repository.watchAll().first, hasLength(existing.length));
    expect(await db.transactionsDao.watchActive().first, isEmpty);
  });

  test('catalog selection writes only with save and reuses a concurrently created category', () async {
    final existing = await repository.watchAll().first;
    final selected = catalog.choice('Tagihan • Listrik', 'expense', existing);
    expect(await repository.watchAll().first, hasLength(existing.length));
    final corrected = (await draft()).copyWith(categoryId: selected.id);
    await repository.save(
      CategoriesCompanion.insert(
        id: 'existing-electricity',
        name: selected.name,
        kind: const Value('expense'),
        createdAt: _dateForTest,
        updatedAt: _dateForTest,
      ),
    );
    final saved = await actions().save(
      original: corrected,
      corrected: corrected,
    );
    expect(saved.categoryId, 'existing-electricity');
    expect(catalog.sameChoice(selected.id, saved.categoryId), isTrue);
    expect(
      (await repository.watchAll().first).where((c) => c.name == selected.name),
      hasLength(1),
    );
  });

  test(
    'new manual catalog category rolls back when the transaction fails',
    () async {
      final existing = await repository.watchAll().first;
      final selected = catalog.choice(
        'Keluarga • Laundry',
        'expense',
        existing,
      );
      final corrected = (await draft()).copyWith(categoryId: selected.id);
      await expectLater(
        actions(memory: _FailingMemory())
            .save(original: corrected, corrected: corrected),
        throwsStateError,
      );
      expect(
        (await repository.watchAll().first).where(
          (c) => c.name == selected.name,
        ),
        isEmpty,
      );
      expect(await db.transactionsDao.watchActive().first, isEmpty);
    },
  );
  test(
    'real parser context exposes Cafe before its first saved transaction',
    () async {
      final before = await repository.watchAll().first;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          parserClockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 10, 8, 10)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(parserContextProvider, (_, _) {});
      final ctx = await container.read(parserContextProvider.future);
      final draft =
          (await container
                  .read(parserPipelineProvider)
                  .parse('minum kopi 35rb pakai Tunai', ctx))
              .single;
      expect(
        ctx.categories.singleWhere((c) => c.id == draft.categoryId).name,
        QuickInputCategories.cafeName,
      );
      expect(await repository.watchAll().first, hasLength(before.length));
      expect(await db.transactionsDao.watchActive().first, isEmpty);
    },
  );
  test(
    'save creates category and transaction atomically; later saves reuse it',
    () async {
      final original = await draft();
      final saved = await actions().save(
        original: original,
        corrected: original,
      );
      expect(saved.categoryId, isNot(original.categoryId));
      await actions().save(original: original, corrected: saved);
      final cafe = (await repository.watchAll().first)
          .where((c) => c.name == QuickInputCategories.cafeName)
          .toList();
      expect(cafe, hasLength(1));
      expect(cafe.single.isDirty, isTrue);
      final rows = await db.transactionsDao.watchActive().first;
      expect(rows, hasLength(2));
      expect(rows.every((row) => row.categoryId == cafe.single.id), isTrue);
      expect(await db.select(db.quickInputMemory).get(), isEmpty);
      await repository.softDelete(cafe.single.id, DateTime.now());
      final replacement = await actions().save(
        original: original,
        corrected: original,
      );
      expect(replacement.categoryId, isNot(cafe.single.id));
      expect(
        (await repository.watchAll().first).where(
          (c) => c.name == QuickInputCategories.cafeName,
        ),
        hasLength(1),
      );
      final archived = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(cafe.single.id))).getSingle();
      expect(archived.deletedAt, isNotNull);
    },
  );
  test(
    'failed ledger/memory save also rolls back the new Cafe category',
    () async {
      final original = await draft();
      await expectLater(
        actions(memory: _FailingMemory())
            .save(original: original, corrected: original),
        throwsStateError,
      );
      expect(
        (await repository.watchAll().first).where(
          (c) => c.name == QuickInputCategories.cafeName,
        ),
        isEmpty,
      );
      expect(await db.transactionsDao.watchActive().first, isEmpty);
    },
  );
  test(
    'a category created during confirmation is reused without duplicate',
    () async {
      final original = await draft();
      await CategoryActions(repository).save(
        id: 'existing-cafe',
        name: QuickInputCategories.cafeName,
        kind: 'expense',
      );
      final saved = await actions().save(
        original: original,
        corrected: original,
      );
      expect(saved.categoryId, 'existing-cafe');
      expect(await db.select(db.quickInputMemory).get(), isEmpty);
      expect(
        catalog.currentId(
          original.categoryId,
          await repository.watchAll().first,
        ),
        'existing-cafe',
      );
      expect(
        (await repository.watchAll().first).where(
          (c) => c.name == QuickInputCategories.cafeName,
        ),
        hasLength(1),
      );
    },
  );
  test('existing standalone Cafe /Warkop is recognized and reused', () async {
    await CategoryActions(repository)
        .save(id: 'legacy-cafe', name: 'Cafe /Warkop', kind: 'expense');
    final existing = await repository.watchAll().first;
    expect(catalog.preview(existing).length, existing.length);
  });
}
