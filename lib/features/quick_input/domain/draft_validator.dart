import 'transaction_draft.dart';

final class DraftValidator {
  const DraftValidator();

  List<DraftWarning> validate(TransactionDraft draft, {DateTime? now}) {
    final problems = <DraftWarning>[];
    if (draft.amount == null) {
      problems.add(
        const DraftWarning(
          field: DraftField.amount,
          code: 'amount_missing',
          message: 'Isi jumlah uang.',
        ),
      );
    } else if (draft.amount! <= 0) {
      problems.add(
        const DraftWarning(
          field: DraftField.amount,
          code: 'amount_not_positive',
          message: 'Jumlah harus lebih dari Rp 0.',
        ),
      );
    }
    if (draft.accountId?.trim().isEmpty ?? true) {
      problems.add(
        const DraftWarning(
          field: DraftField.accountId,
          code: 'account_missing',
          message: 'Pilih akun transaksi.',
        ),
      );
    }
    if (draft.type == TransactionType.transfer) {
      final external =
          draft.toAccountId == null &&
          (draft.recipientName != null || draft.recipientAccount != null);
      if (external) {
        if (draft.recipientName?.trim().isEmpty ?? true) {
          problems.add(
            const DraftWarning(
              field: DraftField.recipientName,
              code: 'recipient_name_missing',
              message: 'Isi nama penerima.',
            ),
          );
        }
        if (draft.recipientAccount?.trim().isEmpty ?? true) {
          problems.add(
            const DraftWarning(
              field: DraftField.recipientAccount,
              code: 'recipient_account_missing',
              message: 'Isi rekening penerima.',
            ),
          );
        }
      } else if (draft.toAccountId?.trim().isEmpty ?? true) {
        problems.add(
          const DraftWarning(
            field: DraftField.toAccountId,
            code: 'destination_missing',
            message: 'Pilih akun tujuan.',
          ),
        );
      } else if (draft.accountId?.trim().isNotEmpty == true &&
          draft.accountId!.trim() == draft.toAccountId!.trim()) {
        problems.add(
          const DraftWarning(
            field: DraftField.toAccountId,
            code: 'same_account',
            message: 'Akun tujuan harus berbeda dari akun asal.',
          ),
        );
      }
    } else if (draft.categoryId?.trim().isEmpty ?? true) {
      problems.add(
        const DraftWarning(
          field: DraftField.categoryId,
          code: 'category_missing',
          message: 'Pilih kategori transaksi.',
        ),
      );
    }
    final cutoff = (now ?? DateTime.now()).toUtc().add(const Duration(days: 1));
    if (draft.occurredAt?.isAfter(cutoff) ?? false) {
      problems.add(
        const DraftWarning(
          field: DraftField.occurredAt,
          code: 'date_too_far_ahead',
          message: 'Tanggal maksimal 1 hari dari sekarang.',
        ),
      );
    }
    return List.unmodifiable(problems);
  }
}
