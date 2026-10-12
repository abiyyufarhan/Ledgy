import '../../transactions/domain/entities/transaction.dart';

export '../../transactions/domain/entities/transaction.dart'
    show TransactionType;

enum DraftSource { text, voice, receipt }

enum DraftField {
  type,
  amount,
  accountId,
  toAccountId,
  recipientName,
  recipientAccount,
  categoryId,
  note,
  occurredAt,
}

/// A parser hint or a validation issue. Parser hints alone do not block saving.
final class DraftWarning {
  const DraftWarning({
    required this.message,
    this.field,
    this.code = 'parser_hint',
  });

  final String message;
  final DraftField? field;
  final String code;
}

final class DraftItem {
  const DraftItem({required this.name, required this.amount});

  final String name;
  final int amount;
}

const _unchanged = Object();

/// An incomplete transaction, independent of persistence and Flutter widgets.
/// Money is integer rupiah; timestamps are normalized to UTC on every copy.
final class TransactionDraft {
  TransactionDraft({
    required this.type,
    this.amount,
    this.accountId,
    this.toAccountId,
    this.recipientName,
    this.recipientAccount,
    this.categoryId,
    this.note,
    DateTime? occurredAt,
    this.confidence = 0,
    this.source = DraftSource.text,
    this.rawText = '',
    this.receiptPhotoPath,
    List<DraftWarning> warnings = const [],
    List<DraftItem> items = const [],
  }) : occurredAt = occurredAt?.toUtc(),
       warnings = List.unmodifiable(warnings),
       items = List.unmodifiable(items) {
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'Harus antara 0 dan 1',
      );
    }
  }

  final TransactionType type;
  final int? amount;
  final String? accountId;
  final String? toAccountId;
  final String? recipientName;
  final String? recipientAccount;
  final String? categoryId;
  final String? note;
  final DateTime? occurredAt;
  final double confidence;
  final DraftSource source;
  final String rawText;

  /// Local image only; never included in a transaction's sync payload.
  final String? receiptPhotoPath;
  final List<DraftWarning> warnings;
  final List<DraftItem> items;

  /// Omission preserves a nullable field; passing null explicitly clears it.
  TransactionDraft copyWith({
    TransactionType? type,
    Object? amount = _unchanged,
    Object? accountId = _unchanged,
    Object? toAccountId = _unchanged,
    Object? recipientName = _unchanged,
    Object? recipientAccount = _unchanged,
    Object? categoryId = _unchanged,
    Object? note = _unchanged,
    Object? occurredAt = _unchanged,
    double? confidence,
    DraftSource? source,
    String? rawText,
    Object? receiptPhotoPath = _unchanged,
    List<DraftWarning>? warnings,
    List<DraftItem>? items,
  }) => TransactionDraft(
    type: type ?? this.type,
    amount: identical(amount, _unchanged) ? this.amount : amount as int?,
    accountId: identical(accountId, _unchanged)
        ? this.accountId
        : accountId as String?,
    toAccountId: identical(toAccountId, _unchanged)
        ? this.toAccountId
        : toAccountId as String?,
    recipientName: identical(recipientName, _unchanged)
        ? this.recipientName
        : recipientName as String?,
    recipientAccount: identical(recipientAccount, _unchanged)
        ? this.recipientAccount
        : recipientAccount as String?,
    categoryId: identical(categoryId, _unchanged)
        ? this.categoryId
        : categoryId as String?,
    note: identical(note, _unchanged) ? this.note : note as String?,
    occurredAt: identical(occurredAt, _unchanged)
        ? this.occurredAt
        : occurredAt as DateTime?,
    confidence: confidence ?? this.confidence,
    source: source ?? this.source,
    rawText: rawText ?? this.rawText,
    receiptPhotoPath: identical(receiptPhotoPath, _unchanged)
        ? this.receiptPhotoPath
        : receiptPhotoPath as String?,
    warnings: warnings ?? this.warnings,
    items: items ?? this.items,
  );
}
