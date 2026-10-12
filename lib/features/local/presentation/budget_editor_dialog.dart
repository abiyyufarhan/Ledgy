import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/mvp_screens.dart' show showLedgyCategoryPicker;
import '../data/local_finance_repository.dart';
import '../../reports/domain/finance_report.dart' show categoryParent;
import 'local_providers.dart';

class BudgetEditorDialog extends ConsumerStatefulWidget {
  const BudgetEditorDialog({
    super.key,
    required this.snapshot,
    required this.month,
    this.existing,
  });
  final FinanceSnapshot snapshot;
  final DateTime month;
  final BudgetProgress? existing;

  @override
  ConsumerState<BudgetEditorDialog> createState() => _BudgetEditorDialogState();
}

class _BudgetEditorDialogState extends ConsumerState<BudgetEditorDialog> {
  late final _amount = TextEditingController(
    text: widget.existing?.budget.amount.toString() ?? '',
  );
  late final _categoryText = TextEditingController(
    text: widget.existing?.category ?? '',
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _categoryText.dispose();
    super.dispose();
  }

  Future<void> _chooseCategory() async {
    final selected = await showLedgyCategoryPicker(
      context,
      type: 'expense',
      existingCategories: widget.snapshot.categories,
    );
    if (selected != null && mounted) {
      setState(
        () => _categoryText.text = categoryParent(selected.databaseName),
      );
    }
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text) ?? 0;
    final category = _categoryText.text.trim();
    if (category.isEmpty || amount <= 0) {
      setState(() => _error = 'Pilih kategori dan isi nominal lebih dari nol.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(localFinanceProvider)
          .saveBudget(category, amount, widget.month);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Anggaran baru' : 'Ubah anggaran'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('budget-date-field'),
              initialValue: DateFormat(
                'MMMM yyyy',
                'id_ID',
              ).format(widget.month),
              readOnly: true,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(labelText: 'Tanggal'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('budget-category-field'),
              controller: _categoryText,
              readOnly: true,
              enableInteractiveSelection: false,
              decoration: InputDecoration(
                labelText: 'Kategori',
                hintText: 'Pilih kategori',
                suffixIcon: widget.existing == null
                    ? const Icon(Icons.expand_more_rounded)
                    : null,
              ),
              onTap: _busy || widget.existing != null ? null : _chooseCategory,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Batas anggaran (Rp)',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Batas kategori mencakup seluruh subkategori dari semua aset. Peringatan dikirim di 80% dan 100%.',
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFFF6380))),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Menyimpan…' : 'Simpan'),
      ),
    ],
  );
}
