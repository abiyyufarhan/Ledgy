import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/mvp_screens.dart' show showLedgyCategoryPicker;
import '../../../core/utils/currency_formatter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_dropdown_field.dart';
import '../../../core/widgets/glass_menu.dart';
import '../../auth/presentation/profile_menu.dart';
import '../../transfer/data/csv_repository.dart';
import '../data/local_finance_repository.dart';
import 'local_automation_host.dart';
import 'local_providers.dart';
import 'budget_progress_card.dart';
import 'budget_editor_dialog.dart';

const _green = Color(0xFF34D399);
const _pink = Color(0xFFFF6380);

void _message(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class _MonthPicker extends StatelessWidget {
  const _MonthPicker(this.month, this.onChanged);
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Bulan sebelumnya',
        onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Text(
          DateFormat('MMMM yyyy', 'id_ID').format(month),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      IconButton(
        tooltip: 'Bulan berikutnya',
        onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class _Snapshot extends ConsumerWidget {
  const _Snapshot({required this.builder});
  final Widget Function(FinanceSnapshot) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(financeSnapshotProvider)
      .when(
        skipLoadingOnReload: true,
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          title: 'Data tidak dapat dimuat',
          message: 'Data lokal belum dapat dibaca. Coba muat ulang.',
          actionLabel: 'Coba lagi',
          onAction: () => ref.invalidate(financeSnapshotProvider),
        ),
      );
}

class BudgetPlansPage extends ConsumerStatefulWidget {
  const BudgetPlansPage({
    super.key,
    this.embedded = false,
    this.appBarTitle,
    this.initialMonth,
  });
  final bool embedded;
  final Widget? appBarTitle;
  final DateTime? initialMonth;
  @override
  ConsumerState<BudgetPlansPage> createState() => _BudgetPlansPageState();
}

class _BudgetPlansPageState extends ConsumerState<BudgetPlansPage> {
  late DateTime _month =
      widget.initialMonth ??
      DateTime(DateTime.now().year, DateTime.now().month);
  @override
  void didUpdateWidget(covariant BudgetPlansPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMonth != oldWidget.initialMonth &&
        widget.initialMonth != null) {
      _month = widget.initialMonth!;
    }
  }

  Future<void> _edit(FinanceSnapshot snapshot, [BudgetProgress? existing]) =>
      showDialog<void>(
        context: context,
        builder: (_) => BudgetEditorDialog(
          snapshot: snapshot,
          month: _month,
          existing: existing,
        ),
      );

  Future<void> _activateNotifications() async {
    try {
      final notifications = ref.read(localNotificationsProvider);
      final allowed = await notifications.requestPermission();
      if (!mounted) return;
      await ref
          .read(localFinanceProvider)
          .checkBudgets(DateTime.now(), notifications.budget);
      if (mounted) {
        _message(
          context,
          allowed
              ? 'Notifikasi diaktifkan. Periksa juga pengaturan notifikasi perangkat.'
              : 'Izin notifikasi belum diberikan.',
        );
      }
    } catch (e) {
      if (mounted) _message(context, 'Notifikasi belum aktif: $e');
    }
  }

  Future<void> _manageBudget(
    BuildContext anchor,
    FinanceSnapshot snapshot,
    BudgetProgress row,
  ) async {
    final selected = await showGlassMenu<String>(
      context: context,
      anchorContext: anchor,
      entries: const [
        GlassMenuEntry(
          value: 'edit',
          label: Text('Ubah anggaran'),
          icon: Icon(Icons.edit_outlined, size: 20),
        ),
        GlassMenuEntry(
          value: 'delete',
          label: Text('Hapus anggaran'),
          icon: Icon(Icons.delete_outline, size: 20),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected.value == 'edit') {
      await _edit(snapshot, row);
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Hapus anggaran?'),
        content: const Text('Riwayat transaksi tetap tersimpan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    try {
      await ref.read(localFinanceProvider).archiveBudget(row.budget.id);
    } catch (e) {
      if (mounted) _message(context, '$e');
    }
  }

  Widget _actionsMenu() => Builder(
    builder: (anchor) {
      final snapshot = ref.watch(financeSnapshotProvider).asData?.value;
      return IconButton(
        key: const ValueKey('budget-actions-menu'),
        tooltip: 'Menu anggaran',
        icon: const Icon(Icons.menu),
        onPressed: snapshot == null
            ? null
            : () async {
                final selected = await showGlassMenu<String>(
                  context: context,
                  anchorContext: anchor,
                  entries: const [
                    GlassMenuEntry(
                      value: 'add',
                      label: Text('Tambah anggaran'),
                      icon: Icon(Icons.add, size: 20),
                    ),
                    GlassMenuEntry(
                      value: 'notifications',
                      label: Text('Aktifkan notifikasi'),
                      icon: Icon(Icons.notifications_active_outlined, size: 20),
                    ),
                  ],
                );
                if (!mounted || selected == null) return;
                if (selected.value == 'add') {
                  await _edit(snapshot);
                } else if (selected.value == 'notifications') {
                  await _activateNotifications();
                }
              },
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded && widget.appBarTitle == null
        ? null
        : AppBar(
            title: widget.appBarTitle ?? const Text('Anggaran bulanan'),
            actions: [
              _actionsMenu(),
              const SizedBox(width: AppTheme.compactSpacing),
            ],
            leading:
                MediaQuery.sizeOf(context).width < AppTheme.sidebarBreakpoint
                ? const ProfileMenu.compact()
                : null,
          ),
    body: _Snapshot(
      builder: (s) {
        final rows = ref.read(localFinanceProvider).budgetProgress(s, _month);
        final automationError = ref.watch(automationErrorProvider);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            AppTheme.pagePadding,
            AppTheme.pagePadding,
            AppTheme.pagePadding,
            widget.embedded
                ? AppTheme.floatingBottomSpace
                : AppTheme.pagePadding,
          ),
          children: [
            _MonthPicker(_month, (month) => setState(() => _month = month)),
            const SizedBox(height: 16),
            if (automationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  automationError,
                  style: const TextStyle(color: _pink),
                ),
              ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: AppTheme.fieldSpacing,
                runSpacing: AppTheme.fieldSpacing,
                children: [
                  for (final row in rows)
                    SizedBox(
                      width: constraints.maxWidth < 320
                          ? constraints.maxWidth
                          : 320,
                      child: Builder(
                        builder: (anchor) => BudgetProgressCard(
                          key: ValueKey('budget-card-${row.budget.id}'),
                          progress: row,
                          onTap: () => _manageBudget(anchor, s, row),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class RecurringPage extends ConsumerStatefulWidget {
  const RecurringPage({super.key, this.embedded = false, this.appBarTitle});
  final bool embedded;
  final Widget? appBarTitle;
  @override
  ConsumerState<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends ConsumerState<RecurringPage> {
  bool _running = false;
  Future<void> _create(FinanceSnapshot s) async {
    final accounts = s.accounts.where((a) => a.deletedAt == null).toList();
    if (accounts.isEmpty) {
      _message(context, 'Tambahkan aset terlebih dahulu.');
      return;
    }
    final amount = TextEditingController();
    final note = TextEditingController();
    final interval = TextEditingController(text: '1');
    var type = 'expense';
    var frequency = 'monthly';
    var accountId = accounts.first.id;
    String? categoryName;
    DateTime next = DateTime.now();
    bool busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Transaksi berulang'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassDropdownFormField<String>(
                    itemIconBuilder: (value) => value == 'income'
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Jenis'),
                    items: const [
                      DropdownMenuItem(
                        value: 'expense',
                        child: Text('Pengeluaran'),
                      ),
                      DropdownMenuItem(
                        value: 'income',
                        child: Text('Pemasukan'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => update(() {
                            type = value!;
                            categoryName = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Nominal (Rp)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassDropdownFormField<String>(
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: 'Aset'),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) => update(() => accountId = value!),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final selected = await showLedgyCategoryPicker(
                              context,
                              type: type,
                              existingCategories: s.categories,
                            );
                            if (selected != null && context.mounted) {
                              update(
                                () => categoryName = selected.databaseName,
                              );
                            }
                          },
                    child: Text(categoryName ?? 'Pilih kategori'),
                  ),
                  const SizedBox(height: 12),
                  GlassDropdownFormField<String>(
                    itemIconBuilder: (value) => switch (value) {
                      'weekly' => Icons.date_range_outlined,
                      'monthly' => Icons.calendar_month_outlined,
                      _ => Icons.today_outlined,
                    },
                    initialValue: frequency,
                    decoration: const InputDecoration(labelText: 'Frekuensi'),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Harian')),
                      DropdownMenuItem(
                        value: 'weekly',
                        child: Text('Mingguan'),
                      ),
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text('Bulanan'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => update(() => frequency = value!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: interval,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Setiap berapa hari / minggu / bulan',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mulai'),
                    subtitle: Text(formatTransactionDateTime(next)),
                    trailing: const Icon(Icons.event),
                    onTap: busy
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: next,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (date == null || !context.mounted) return;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(next),
                              builder: (context, child) => MediaQuery(
                                data: MediaQuery.of(context)
                                    .copyWith(alwaysUse24HourFormat: true),
                                child: child!,
                              ),
                            );
                            if (time != null && context.mounted) {
                              update(
                                () => next = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  time.hour,
                                  time.minute,
                                ),
                              );
                            }
                          },
                  ),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (gaji, tagihan, cicilan…)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tanggal yang sudah jatuh tempo akan dibuat otomatis, termasuk jadwal terlewat. Di Android, jadwal latar belakang mengikuti kebijakan baterai perangkat.',
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: _pink)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final value = int.tryParse(amount.text) ?? 0;
                      final every = int.tryParse(interval.text) ?? 0;
                      if (value <= 0 || every <= 0 || categoryName == null) {
                        update(
                          () => error =
                              'Isi nominal, interval, dan kategori yang valid.',
                        );
                        return;
                      }
                      update(() => busy = true);
                      try {
                        final repo = ref.read(localFinanceProvider);
                        final categoryId = await repo.ensureCategory(
                          categoryName!,
                          type,
                        );
                        await repo.saveRule(
                          type: type,
                          amount: value,
                          accountId: accountId,
                          categoryId: categoryId,
                          note: note.text.trim(),
                          frequency: frequency,
                          interval: every,
                          next: next,
                        );
                        await repo.generateDue(DateTime.now());
                        if (dialog.mounted) Navigator.pop(dialog);
                      } catch (e) {
                        if (context.mounted) {
                          update(() {
                            busy = false;
                            error = '$e';
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Menyimpan…' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    note.dispose();
    interval.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded && widget.appBarTitle == null
        ? null
        : AppBar(
            title: widget.appBarTitle ?? const Text('Transaksi berulang'),
            leading:
                MediaQuery.sizeOf(context).width < AppTheme.sidebarBreakpoint
                ? const ProfileMenu.compact()
                : null,
          ),
    body: _Snapshot(
      builder: (s) {
        final accounts = {for (final a in s.accounts) a.id: a.name};
        final rules = s.rules.where((r) => r.deletedAt == null).toList();
        final error = ref.watch(automationErrorProvider);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            AppTheme.pagePadding,
            AppTheme.pagePadding,
            AppTheme.pagePadding,
            widget.embedded
                ? AppTheme.floatingBottomSpace
                : AppTheme.pagePadding,
          ),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => _create(s),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah jadwal'),
                ),
                OutlinedButton.icon(
                  onPressed: _running
                      ? null
                      : () async {
                          setState(() => _running = true);
                          try {
                            final repo = ref.read(localFinanceProvider);
                            final count = await repo.generateDue(
                              DateTime.now(),
                            );
                            await repo.checkBudgets(
                              DateTime.now(),
                              ref.read(localNotificationsProvider).budget,
                            );
                            if (context.mounted) {
                              _message(
                                context,
                                '$count transaksi jatuh tempo dibuat.',
                              );
                            }
                          } catch (e) {
                            if (context.mounted) _message(context, '$e');
                          } finally {
                            if (mounted) setState(() => _running = false);
                          }
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Proses jatuh tempo'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Otomatis saat aplikasi dibuka atau aktif kembali. Jadwal yang dijeda tidak dibuat; saat dilanjutkan, jadwal terlewat ikut diproses.',
            ),
            if (error != null)
              Text(error, style: const TextStyle(color: _pink)),
            const SizedBox(height: 20),
            if (rules.isEmpty) const Text('Belum ada transaksi berulang.'),
            for (final rule in rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rule.note?.isNotEmpty == true
                                  ? rule.note!
                                  : s.categoryNames[rule.categoryId] ??
                                        'Transaksi berulang',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Switch(
                            value: rule.isActive,
                            onChanged: (value) async {
                              try {
                                await ref
                                    .read(localFinanceProvider)
                                    .toggleRule(rule.id, value);
                              } catch (e) {
                                if (context.mounted) _message(context, '$e');
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Hapus jadwal',
                            onPressed: () async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (dialog) => AlertDialog(
                                  title: const Text('Hapus jadwal?'),
                                  content: const Text(
                                    'Transaksi yang sudah dibuat tidak ikut dihapus.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, false),
                                      child: const Text('Tidak'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, true),
                                      child: const Text('Ya'),
                                    ),
                                  ],
                                ),
                              );
                              if (yes == true) {
                                try {
                                  await ref
                                      .read(localFinanceProvider)
                                      .archiveRule(rule.id);
                                } catch (e) {
                                  if (context.mounted) _message(context, '$e');
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text(
                        '${formatRupiah(rule.amount)} · ${accounts[rule.accountId] ?? 'Aset diarsipkan'}',
                        style: TextStyle(
                          color: rule.type == 'income' ? _green : _pink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Setiap ${rule.interval} ${{'daily': 'hari', 'weekly': 'minggu', 'monthly': 'bulan'}[rule.frequency]} · ${rule.isActive ? 'Aktif' : 'Dijeda'}',
                      ),
                      Text(
                        'Berikutnya: ${formatTransactionDateTime(rule.nextOccurrenceAt)}',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class CsvPage extends ConsumerStatefulWidget {
  const CsvPage({super.key});
  @override
  ConsumerState<CsvPage> createState() => _CsvPageState();
}

class _CsvPageState extends ConsumerState<CsvPage> {
  bool _busy = false;
  String? _content;
  List<CsvRow> _rows = [];
  Future<void> _task(Future<void> Function() operation) async {
    setState(() => _busy = true);
    try {
      await operation();
    } catch (e) {
      if (mounted) _message(context, 'CSV: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _rows.where((r) => r.status == ImportStatus.ready).length;
    final duplicates = _rows
        .where((r) => r.status == ImportStatus.duplicate)
        .length;
    final invalid = _rows.where((r) => r.status == ImportStatus.invalid).length;
    final repo = CsvRepository(ref.read(localFinanceProvider));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ekspor / impor CSV'),
        leading: MediaQuery.sizeOf(context).width < AppTheme.sidebarBreakpoint
            ? const ProfileMenu.compact()
            : null,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Semua transaksi aktif dari seluruh aset diekspor. Impor memakai nominal rupiah bulat dan tanggal ISO-8601 dengan zona waktu.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aset pada CSV harus sudah ada (ID atau nama yang sama). Kategori yang belum ada akan dibuat hanya setelah konfirmasi. Duplikat diperiksa melalui ID dan isi transaksi, termasuk transaksi yang pernah dihapus.',
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _task(() async {
                                final csv = await repo.export();
                                final path = await FilePicker.saveFile(
                                  fileName:
                                      'ledgy-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.csv',
                                  bytes: Uint8List.fromList(utf8.encode(csv)),
                                  mimeType: 'text/csv',
                                );
                                if (path != null && context.mounted) {
                                  _message(context, 'CSV berhasil disimpan.');
                                }
                              }),
                        icon: const Icon(Icons.download),
                        label: const Text('Ekspor CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _task(() async {
                                final files = await FilePicker.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['csv'],
                                );
                                if (files.isEmpty) return;
                                if (mounted) {
                                  setState(() {
                                    _content = null;
                                    _rows = [];
                                  });
                                }
                                final file = files.first;
                                if ((await file.length() ?? 0) >
                                    10 * 1024 * 1024) {
                                  throw const FormatException(
                                    'Ukuran CSV maksimal 10 MB.',
                                  );
                                }
                                final bytes = await file.readAsBytes();
                                if (bytes.length > 10 * 1024 * 1024) {
                                  throw const FormatException(
                                    'Ukuran CSV maksimal 10 MB.',
                                  );
                                }
                                final content = utf8.decode(bytes);
                                final rows = await repo.preview(content);
                                if (mounted) {
                                  setState(() {
                                    _content = content;
                                    _rows = rows;
                                  });
                                }
                              }),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Pilih CSV'),
                      ),
                    ],
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 22),
                  if (_content != null) ...[
                    Text(
                      'Pratinjau: $ready siap · $duplicates duplikat · $invalid tidak valid',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy || ready == 0
                          ? null
                          : () => _task(() async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (dialog) => AlertDialog(
                                  title: const Text('Impor transaksi?'),
                                  content: Text(
                                    '$ready transaksi akan ditambahkan. $duplicates duplikat dan $invalid baris tidak valid akan dilewati. Saldo dan laporan akan ikut diperbarui.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, false),
                                      child: const Text('Batal'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, true),
                                      child: const Text('Impor'),
                                    ),
                                  ],
                                ),
                              );
                              if (yes != true) return;
                              final count = await repo.import(_content!);
                              final rows = await repo.preview(_content!);
                              if (context.mounted) {
                                setState(() => _rows = rows);
                                _message(
                                  context,
                                  '$count transaksi berhasil diimpor.',
                                );
                              }
                            }),
                      child: Text('Impor $ready transaksi valid'),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              final color = switch (row.status) {
                ImportStatus.ready => _green,
                ImportStatus.duplicate => Colors.amber,
                ImportStatus.invalid => _pink,
              };
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: GlassCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (row.status) {
                      ImportStatus.ready => Icons.check_circle_outline,
                      ImportStatus.duplicate => Icons.copy,
                      ImportStatus.invalid => Icons.error_outline,
                    }, color: color),
                    title: Text(
                      'Baris ${row.line} · ${switch (row.status) {
                        ImportStatus.ready => 'Siap',
                        ImportStatus.duplicate => 'Duplikat',
                        ImportStatus.invalid => 'Tidak valid',
                      }}',
                    ),
                    subtitle: Text(row.description),
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
