import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../domain/draft_validator.dart';
import '../domain/quick_input_memory_repository.dart';
import '../domain/transaction_draft.dart';
import 'quick_input_categories.dart';
import 'receipt_storage.dart';

import 'package:uuid/uuid.dart';

/// One atomic commit: the existing transaction repository plus local learning.
final class QuickInputActions {
  const QuickInputActions(
    this.db,
    this.transactions,
    this.memory, {
    this.categories,
    this.receipts,
  });
  final AppDatabase db;
  final TransactionActions transactions;
  final QuickInputMemoryRepository memory;
  final QuickInputCategories? categories;
  final ReceiptStorage? receipts;

  Future<TransactionDraft> save({
    required TransactionDraft original,
    required TransactionDraft corrected,
  }) async {
    if (const DraftValidator().validate(corrected).isNotEmpty ||
        corrected.occurredAt == null) {
      throw ArgumentError('Draf belum lengkap untuk disimpan.');
    }
    String? photo;
    if (corrected.receiptPhotoPath != null &&
        receipts != null &&
        await receipts!.enabled()) {
      photo = await receipts!.stage(corrected.receiptPhotoPath!);
    }
    try {
      return await db.transaction(() async {
        final saved = await categories?.materialize(corrected) ?? corrected;
        final transactionId = const Uuid().v4();
        await transactions.save(
          id: transactionId,
          type: saved.type.name,
          amount: saved.amount!,
          accountId: saved.accountId!,
          toAccountId: saved.type == TransactionType.transfer
              ? saved.toAccountId
              : null,
          recipientName:
              saved.type == TransactionType.transfer &&
                  saved.toAccountId == null
              ? saved.recipientName?.trim()
              : null,
          recipientAccount:
              saved.type == TransactionType.transfer &&
                  saved.toAccountId == null
              ? saved.recipientAccount?.trim()
              : null,
          categoryId: saved.type == TransactionType.transfer
              ? null
              : saved.categoryId,
          note: saved.note,
          occurredAt: saved.occurredAt!,
        );
        if (photo != null) await receipts!.link(transactionId, photo);
        // Resolving a preview to an existing ID is not a user correction.
        final sameCategory =
            categories?.sameChoice(original.categoryId, saved.categoryId) ??
            (original.categoryId == saved.categoryId);
        final learnedOriginal = sameCategory
            ? original.copyWith(categoryId: saved.categoryId)
            : original;
        await memory.learn(learnedOriginal, saved);
        return saved.copyWith(receiptPhotoPath: photo);
      });
    } catch (_) {
      if (photo != null) await receipts!.remove(photo);
      rethrow;
    }
  }
}
