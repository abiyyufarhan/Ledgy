import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/quick_input/domain/draft_validator.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

void main() {
  final now = DateTime.utc(2026, 10, 8, 12);
  final complete = TransactionDraft(
    type: TransactionType.expense,
    amount: 25000,
    accountId: 'cash',
    categoryId: 'food',
    occurredAt: now,
  );
  List<String> codes(TransactionDraft draft) => const DraftValidator()
      .validate(draft, now: now)
      .map((w) => w.code)
      .toList();

  test('draf lengkap valid untuk pemasukan dan pengeluaran', () {
    for (final type in [TransactionType.income, TransactionType.expense]) {
      expect(codes(complete.copyWith(type: type)), isEmpty);
    }
  });
  test('jumlah kosong', () {
    expect(codes(complete.copyWith(amount: null)), ['amount_missing']);
  });
  for (final amount in [0, -1, -25000]) {
    test('jumlah $amount ditolak', () {
      expect(codes(complete.copyWith(amount: amount)), ['amount_not_positive']);
    });
  }
  for (final account in <String?>[null, '', '  ']) {
    test('akun kosong: $account', () {
      expect(codes(complete.copyWith(accountId: account)), ['account_missing']);
    });
  }
  for (final destination in <String?>[null, '', '  ']) {
    test('transfer tanpa akun tujuan: $destination', () {
      expect(
        codes(
          complete.copyWith(
            type: TransactionType.transfer,
            toAccountId: destination,
          ),
        ),
        ['destination_missing'],
      );
    });
  }
  test('transfer dengan akun asal dan tujuan sama', () {
    expect(
      codes(
        complete.copyWith(type: TransactionType.transfer, toAccountId: 'cash'),
      ),
      ['same_account'],
    );
    expect(
      codes(
        complete.copyWith(
          type: TransactionType.transfer,
          toAccountId: ' cash ',
        ),
      ),
      ['same_account'],
    );
  });
  test('transfer ke akun berbeda valid tanpa kategori', () {
    expect(
      codes(
        complete.copyWith(
          type: TransactionType.transfer,
          toAccountId: 'bank',
          categoryId: null,
        ),
      ),
      isEmpty,
    );
  });

  test(
    'transfer ke penerima eksternal valid tanpa akun tujuan dan kategori',
    () {
      expect(
        codes(
          complete.copyWith(
            type: TransactionType.transfer,
            categoryId: null,
            recipientName: 'Budi',
            recipientAccount: '00123456',
          ),
        ),
        isEmpty,
      );
    },
  );

  for (final blank in <String?>[null, '', '  ']) {
    test('nama penerima kosong ditolak: $blank', () {
      expect(
        codes(
          complete.copyWith(
            type: TransactionType.transfer,
            recipientName: blank,
            recipientAccount: '00123456',
          ),
        ),
        ['recipient_name_missing'],
      );
    });
    test('rekening penerima kosong ditolak: $blank', () {
      expect(
        codes(
          complete.copyWith(
            type: TransactionType.transfer,
            recipientName: 'Budi',
            recipientAccount: blank,
          ),
        ),
        ['recipient_account_missing'],
      );
    });
  }

  test('data penerima tidak meloloskan transfer ke akun asal sendiri', () {
    expect(
      codes(
        complete.copyWith(
          type: TransactionType.transfer,
          toAccountId: 'cash',
          recipientName: 'Budi',
          recipientAccount: '00123',
        ),
      ),
      ['same_account'],
    );
  });
  for (final type in [TransactionType.income, TransactionType.expense]) {
    test('kategori kosong untuk ${type.name}', () {
      for (final category in <String?>[null, '', ' ']) {
        expect(codes(complete.copyWith(type: type, categoryId: category)), [
          'category_missing',
        ]);
      }
    });
  }
  test('tanggal lebih dari satu hari di masa depan ditolak', () {
    expect(
      codes(
        complete.copyWith(
          occurredAt: now.add(const Duration(days: 1, microseconds: 1)),
        ),
      ),
      ['date_too_far_ahead'],
    );
  });
  test('batas tepat 24 jam, masa lalu, dan tanggal kosong valid', () {
    for (final date in <DateTime?>[
      null,
      now.subtract(const Duration(days: 100)),
      now.add(const Duration(days: 1)),
    ]) {
      expect(codes(complete.copyWith(occurredAt: date)), isEmpty);
    }
  });
  test('mengembalikan seluruh masalah dengan kolom dan bantuan', () {
    final issues = const DraftValidator().validate(
      TransactionDraft(
        type: TransactionType.expense,
        occurredAt: now.add(const Duration(days: 2)),
      ),
      now: now,
    );
    expect(issues.map((i) => i.field), [
      DraftField.amount,
      DraftField.accountId,
      DraftField.categoryId,
      DraftField.occurredAt,
    ]);
    expect(issues.every((i) => i.message.isNotEmpty), isTrue);
  });
  test('peringatan parser tidak menjadi masalah validator', () {
    expect(
      codes(
        complete.copyWith(
          warnings: [const DraftWarning(message: 'Periksa merchant.')],
        ),
      ),
      isEmpty,
    );
  });
  test(
    'copyWith dapat mempertahankan dan mengosongkan semua kolom nullable',
    () {
      final draft = complete.copyWith(
        toAccountId: 'bank',
        note: 'Makan',
        recipientName: 'Budi',
        recipientAccount: '00123',
      );
      final copied = draft.copyWith(confidence: .8);
      expect(copied.accountId, draft.accountId);
      expect(copied.note, draft.note);
      expect(copied.occurredAt, draft.occurredAt);
      expect(copied.recipientName, 'Budi');
      expect(copied.recipientAccount, '00123');
      final cleared = draft.copyWith(
        amount: null,
        accountId: null,
        toAccountId: null,
        recipientName: null,
        recipientAccount: null,
        categoryId: null,
        note: null,
        occurredAt: null,
      );
      expect([
        cleared.amount,
        cleared.accountId,
        cleared.toAccountId,
        cleared.recipientName,
        cleared.recipientAccount,
        cleared.categoryId,
        cleared.note,
        cleared.occurredAt,
      ], everyElement(isNull));
      expect(draft.amount, 25000);
    },
  );
  test('tanggal pada konstruksi dan copy dinormalisasi ke UTC', () {
    final local = DateTime(2026, 10, 8, 10, 45);
    final draft = complete.copyWith(occurredAt: local);
    expect(draft.occurredAt!.isUtc, isTrue);
    expect(draft.occurredAt, local.toUtc());
  });
  test('daftar item dan peringatan disalin dan tidak bisa diubah', () {
    final items = [const DraftItem(name: 'Nasi', amount: 25000)];
    final warnings = [const DraftWarning(message: 'Periksa jumlah.')];
    final draft = complete.copyWith(items: items, warnings: warnings);
    items.clear();
    warnings.clear();
    expect(draft.items.single.name, 'Nasi');
    expect(draft.warnings, hasLength(1));
    expect(() => draft.items.clear(), throwsUnsupportedError);
    expect(() => draft.warnings.clear(), throwsUnsupportedError);
  });
  test('keyakinan harus hingga dan berada dalam 0–1', () {
    for (final value in [-.1, 1.1, double.nan, double.infinity]) {
      expect(() => complete.copyWith(confidence: value), throwsArgumentError);
    }
    expect(complete.copyWith(confidence: 0).confidence, 0);
    expect(complete.copyWith(confidence: 1).confidence, 1);
  });
}
