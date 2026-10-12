import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../local/data/local_finance_repository.dart';
import '../../reports/domain/finance_report.dart';
import '../domain/ledger_csv.dart';

enum ImportStatus { ready, duplicate, invalid }

class CsvRow {
  const CsvRow(this.line, this.status, this.description, {this.values});
  final int line;
  final ImportStatus status;
  final String description;
  final Map<String, String>? values;
}

class CsvRepository {
  CsvRepository(this.finance);
  final LocalFinanceRepository finance;

  Future<String> export({Set<String>? transactionIds}) async {
    final s = await finance.snapshot();
    final accounts = {for (final a in s.accounts) a.id: a.name};
    return LedgerCsv.encode([
      LedgerCsv.exportHeaders,
      for (final t in s.transactions)
        if (t.deletedAt == null &&
            (transactionIds == null || transactionIds.contains(t.id)))
          [
            t.id,
            t.type,
            '${t.amount}',
            t.accountId,
            LedgerCsv.safeText(accounts[t.accountId] ?? ''),
            t.toAccountId ?? '',
            LedgerCsv.safeText(accounts[t.toAccountId] ?? ''),
            t.categoryId ?? '',
            LedgerCsv.safeText(s.categoryNames[t.categoryId] ?? ''),
            LedgerCsv.safeText(t.note ?? ''),
            t.occurredAt.toUtc().toIso8601String(),
            LedgerCsv.safeText(t.recipientName ?? ''),
            LedgerCsv.safeText(t.recipientAccount ?? ''),
          ],
    ]);
  }

  String _fingerprint(Transaction t, FinanceSnapshot s) =>
      LedgerCsv.fingerprint(
        type: t.type,
        amount: t.amount,
        accountId: t.accountId,
        toAccountId: t.toAccountId,
        recipientName: t.recipientName,
        recipientAccount: t.recipientAccount,
        categoryId: canonicalCategory(s.categoryNames[t.categoryId] ?? ''),
        note: t.note,
        date: t.occurredAt,
      );

  List<CsvRow> _preview(List<Map<String, String>> input, FinanceSnapshot s) {
    if (input.length > 10000) {
      throw const FormatException('Maksimal 10.000 transaksi per impor.');
    }
    final ids = s.transactions.map((t) => t.id).toSet();
    final fingerprints = s.transactions.map((t) => _fingerprint(t, s)).toSet();
    final result = <CsvRow>[];
    for (var i = 0; i < input.length; i++) {
      final raw = input[i];
      try {
        String v(String key) => LedgerCsv.originalText(raw[key] ?? '');
        final type = v('type').trim();
        final amount = int.tryParse(v('amount'));
        final dateText = v('occurred_at');
        // Require explicit timezone: importing ambiguous times silently shifts dates.
        final date = LedgerCsv.parseDate(dateText);
        if (!['income', 'expense', 'transfer'].contains(type) ||
            amount == null ||
            amount <= 0 ||
            date == null) {
          throw const FormatException(
            'Type/amount/tanggal tidak valid; tanggal harus ISO-8601 dengan zona waktu.',
          );
        }
        String asset(String idKey, String nameKey) {
          final byId = s.accounts.where(
            (a) => a.deletedAt == null && a.id == v(idKey),
          );
          if (byId.isNotEmpty) return byId.first.id;
          final byName = s.accounts.where(
            (a) =>
                a.deletedAt == null &&
                a.name.toLowerCase() == v(nameKey).trim().toLowerCase(),
          );
          if (byName.length == 1) return byName.first.id;
          throw FormatException(
            'Aset "${v(nameKey)}" belum ada atau tidak unik. Buat aset sebelum impor.',
          );
        }

        final account = asset('account_id', 'account_name');
        final recipientName = v('recipient_name').trim();
        final recipientAccount = v('recipient_account').trim();
        final external =
            recipientName.isNotEmpty || recipientAccount.isNotEmpty;
        if (external &&
            (type != 'transfer' ||
                recipientName.isEmpty ||
                recipientAccount.isEmpty ||
                v('to_account_id').isNotEmpty ||
                v('to_account_name').isNotEmpty)) {
          throw const FormatException(
            'Nama dan rekening penerima wajib diisi untuk transfer eksternal.',
          );
        }
        final target = type == 'transfer' && !external
            ? asset('to_account_id', 'to_account_name')
            : '';
        if (target == account) {
          throw const FormatException('Aset tujuan transfer harus berbeda.');
        }
        final categoryById = s.categories.where(
          (c) =>
              c.deletedAt == null && c.id == v('category_id') && c.kind == type,
        );
        final category = type == 'transfer'
            ? ''
            : canonicalCategory(
                categoryById.isNotEmpty
                    ? categoryById.first.name
                    : v('category_name').trim(),
              );
        if (type != 'transfer' && category.isEmpty) {
          throw const FormatException(
            'Kategori wajib untuk pemasukan/pengeluaran.',
          );
        }
        final values = <String, String>{
          'id': v('id'),
          'type': type,
          'amount': '$amount',
          'account_id': account,
          'to_account_id': target,
          'recipient_name': recipientName,
          'recipient_account': recipientAccount,
          'category_name': category,
          'note': v('note'),
          'occurred_at': date.toUtc().toIso8601String(),
        };
        final fingerprint = LedgerCsv.fingerprint(
          type: type,
          amount: amount,
          accountId: account,
          toAccountId: target,
          recipientName: recipientName,
          recipientAccount: recipientAccount,
          categoryId: category,
          note: values['note'],
          date: date,
        );
        final duplicate =
            (v('id').isNotEmpty && ids.contains(v('id'))) ||
            fingerprints.contains(fingerprint);
        if (v('id').isNotEmpty) ids.add(v('id'));
        fingerprints.add(fingerprint);
        result.add(
          CsvRow(
            i + 2,
            duplicate ? ImportStatus.duplicate : ImportStatus.ready,
            '${{'income': 'Pemasukan', 'expense': 'Pengeluaran', 'transfer': 'Transfer'}[type]} · Rp $amount\n'
            '${s.accounts.firstWhere((a) => a.id == account).name}'
            '${target.isEmpty ? '' : ' → ${s.accounts.firstWhere((a) => a.id == target).name}'} · $category\n'
            '${external ? 'Penerima: $recipientName • $recipientAccount\n' : ''}'
            '${date.toLocal()} · ${v('note')}',
            values: values,
          ),
        );
      } on FormatException catch (error) {
        result.add(
          CsvRow(i + 2, ImportStatus.invalid, error.message.toString()),
        );
      }
    }
    return result;
  }

  Future<List<CsvRow>> preview(String content) async =>
      _preview(LedgerCsv.decode(content), await finance.snapshot());

  /// Revalidate inside the write transaction so a stale preview never creates
  /// duplicate entries, nor references an asset archived after preview.
  Future<int> import(String content) => finance.db.transaction(() async {
    await finance.setState(
      'csv:lock',
      DateTime.now().toUtc().toIso8601String(),
    );
    final rows = _preview(LedgerCsv.decode(content), await finance.snapshot());
    final now = DateTime.now().toUtc();
    var count = 0;
    for (final row in rows.where((r) => r.status == ImportStatus.ready)) {
      final v = row.values!;
      final category = v['type'] == 'transfer'
          ? null
          : await finance.ensureCategory(v['category_name']!, v['type']!);
      final externalId = v['id']!;
      final validId = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(externalId);
      await finance.db
          .into(finance.db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: validId ? externalId : const Uuid().v4(),
              type: v['type']!,
              amount: int.parse(v['amount']!),
              accountId: v['account_id']!,
              toAccountId: Value(
                v['to_account_id']!.isEmpty ? null : v['to_account_id'],
              ),
              recipientName: Value(
                v['recipient_name']!.isEmpty ? null : v['recipient_name'],
              ),
              recipientAccount: Value(
                v['recipient_account']!.isEmpty ? null : v['recipient_account'],
              ),
              categoryId: Value(category),
              note: Value(v['note']!.isEmpty ? null : v['note']),
              occurredAt: DateTime.parse(v['occurred_at']!),
              createdAt: now,
              updatedAt: now,
            ),
          );
      count++;
    }
    return count;
  });
}
