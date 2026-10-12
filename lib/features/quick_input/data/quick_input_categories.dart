import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../categories/data/repositories/categories_repository_impl.dart';
import '../../categories/domain/category_catalog.dart';
import '../domain/transaction_draft.dart';

/// A catalog choice can be previewed without writing a category or transaction.
final class QuickInputCategories {
  QuickInputCategories(this.repository);
  final CategoriesRepository repository;
  static const cafeName = 'Makan & Minum • Cafe / Warkop';
  Category? _cafe;
  String? _savedCafeId;
  final _choices = <String, Category>{};
  final _savedIds = <String, String>{};

  String _name(Category category) => category.kind == 'income'
      ? incomeCategoryName(category.name)
      : category.name;

  /// Choosing a catalog entry only prepares it; saving owns the database write.
  Category choice(String name, String kind, List<Category> existing) {
    final match = existing
        .where((c) => c.kind == kind && c.deletedAt == null && _name(c) == name)
        .firstOrNull;
    if (match != null) return match;
    final key = '$kind:$name';
    return _choices.putIfAbsent(key, () {
      final now = DateTime.now().toUtc();
      return Category(
        id: const Uuid().v4(),
        name: name,
        kind: kind,
        createdAt: now,
        updatedAt: now,
        isDirty: true,
      );
    });
  }

  bool _isCafe(Category category) =>
      category.kind == 'expense' &&
      category.name
              .split('•')
              .last
              .trim()
              .toLowerCase()
              .replaceAll('é', 'e')
              .replaceAll(RegExp(r'\s*/\s*'), ' / ') ==
          'cafe / warkop';

  List<Category> preview(List<Category> existing) {
    final selected = _choices.values.where(
      (preview) => !existing.any(
        (c) => c.kind == preview.kind && _name(c) == _name(preview),
      ),
    );
    if (existing.any(_isCafe)) {
      return List.unmodifiable([...existing, ...selected]);
    }
    final now = DateTime.now().toUtc();
    _cafe ??= Category(
      id: const Uuid().v4(),
      name: cafeName,
      kind: 'expense',
      createdAt: now,
      updatedAt: now,
      isDirty: true,
    );
    return List.unmodifiable([...existing, _cafe!, ...selected]);
  }

  String? currentId(String? id, List<Category> existing) {
    final choice = _choices.values.where((c) => c.id == id).firstOrNull;
    if (choice != null) {
      return existing
              .where((c) => c.kind == choice.kind && _name(c) == _name(choice))
              .firstOrNull
              ?.id ??
          id;
    }
    if (id == null || id != _cafe?.id) return id;
    final resolved = existing.where(_isCafe).firstOrNull?.id ?? id;
    _savedCafeId = resolved;
    return resolved;
  }

  bool sameChoice(String? first, String? second) =>
      first == second ||
      (first != null && _savedIds[first] == second && second != null) ||
      (first != null && first == _cafe?.id && second == _savedCafeId);

  /// Called inside the same transaction as the ledger save and local memory.
  Future<TransactionDraft> materialize(TransactionDraft draft) async {
    final selected = _choices.values
        .where((c) => c.id == draft.categoryId)
        .firstOrNull;
    if (selected != null) {
      if (selected.kind != draft.type.name) {
        throw ArgumentError('Kategori tidak sesuai dengan jenis transaksi.');
      }
      final existing = (await repository.watchAll().first)
          .where((c) => c.kind == selected.kind && _name(c) == _name(selected))
          .firstOrNull;
      final id = existing?.id ?? const Uuid().v4();
      if (existing == null) {
        final now = DateTime.now().toUtc();
        await repository.save(
          CategoriesCompanion.insert(
            id: id,
            name: selected.name,
            kind: Value(selected.kind),
            createdAt: now,
            updatedAt: now,
            isDirty: const Value(true),
          ),
        );
      }
      _savedIds[selected.id] = id;
      return draft.copyWith(categoryId: id);
    }
    if (_cafe == null || draft.categoryId != _cafe!.id) return draft;
    if (draft.type != TransactionType.expense) {
      throw ArgumentError('Cafe / Warkop hanya untuk pengeluaran.');
    }
    final existing = (await repository.watchAll().first)
        .where(_isCafe)
        .firstOrNull;
    if (existing != null) {
      _savedCafeId = existing.id;
      return draft.copyWith(categoryId: existing.id);
    }
    final now = DateTime.now().toUtc();
    // Preview IDs never become stored IDs, so a later archived category
    // cannot be accidentally reused by this session's preview.
    final id = const Uuid().v4();
    await repository.save(
      CategoriesCompanion.insert(
        id: id,
        name: cafeName,
        kind: const Value('expense'),
        createdAt: now,
        updatedAt: now,
        isDirty: const Value(true),
      ),
    );
    _savedCafeId = id;
    return draft.copyWith(categoryId: id);
  }
}
