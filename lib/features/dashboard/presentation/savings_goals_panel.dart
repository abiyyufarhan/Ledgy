import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/savings_goal_repository.dart';
import 'dashboard_widgets.dart';

class SavingsGoalsPanel extends ConsumerWidget {
  const SavingsGoalsPanel({super.key});
  Future<void> _edit(BuildContext context, SavingsGoal? goal) => showDialog(
    context: context,
    builder: (_) => _GoalDialog(goal: goal),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) => DashboardPanel(
    title: 'Target Tabungan',
    action: IconButton(
      tooltip: 'Tambah target tabungan',
      key: const ValueKey('dashboard-add-goal'),
      onPressed: () => _edit(context, null),
      icon: const Icon(Icons.add, size: 20),
    ),
    child: ref
        .watch(savingsGoalsProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton.icon(
            onPressed: () => ref.invalidate(savingsGoalsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang target tabungan'),
          ),
          data: (goals) => goals.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mulai menabung untuk hal yang ingin kamu capai.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _edit(context, null),
                      icon: const Icon(Icons.savings_outlined, size: 20),
                      label: const Text('Buat target'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    for (final goal in goals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => _edit(context, goal),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        goal.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${NumberFormat('0.#', 'id_ID').format(goal.progress * 100)}%',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${formatRupiah(goal.saved)} / ${formatRupiah(goal.target)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.mutedText),
                                ),
                                const SizedBox(height: 10),
                                DashboardProgress(
                                  value: goal.progress,
                                  color: dashboardIncome,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
  );
}

class _GoalDialog extends ConsumerStatefulWidget {
  const _GoalDialog({this.goal});
  final SavingsGoal? goal;
  @override
  ConsumerState<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends ConsumerState<_GoalDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.goal?.name ?? '');
  late final _target = TextEditingController(
    text: widget.goal?.target.toString() ?? '',
  );
  late final _saved = TextEditingController(
    text: widget.goal?.saved.toString() ?? '0',
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(savingsGoalsProvider.notifier)
          .save(
            id: widget.goal?.id,
            name: _name.text,
            target: int.parse(_target.text),
            saved: int.parse(_saved.text),
          );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Target belum tersimpan. Coba lagi.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus target tabungan?'),
        content: Text(widget.goal!.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(savingsGoalsProvider.notifier).remove(widget.goal!.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Target belum terhapus. Coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.goal == null ? 'Target tabungan baru' : 'Ubah target tabungan',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_busy,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Nama target'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Isi nama target.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _target,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Target (Rp)'),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                    ? 'Isi nominal lebih dari nol.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _saved,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Jumlah terkumpul (Rp)',
                ),
                validator: (v) => int.tryParse(v ?? '') == null
                    ? 'Isi jumlah terkumpul.'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'Perbarui jumlah terkumpul sesuai tabunganmu. Saldo aset tetap dihitung dari transaksi.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (widget.goal != null)
        TextButton(
          onPressed: _busy ? null : _delete,
          child: const Text('Hapus'),
        ),
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
