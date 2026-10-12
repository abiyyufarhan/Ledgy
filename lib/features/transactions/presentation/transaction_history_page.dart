import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/profile_menu.dart';
import '../../local/data/local_finance_repository.dart';
import '../../reports/data/finance_report_exporter.dart';
import '../domain/transaction_filters.dart';
import '../domain/transaction_period.dart';
import 'transaction_filter_dialog.dart';
import 'transaction_report_download_menu.dart';
import 'transaction_toolbar_icon.dart';

/// Injectable so tests never open a native save dialog or export private data.
final transactionReportExportProvider =
    Provider<Future<bool> Function(TransactionReport, FinanceReportFormat)>((
      ref,
    ) {
      return (report, format) async {
        final bytes = await FinanceReportExporter.encode(report, format);
        final path = await FilePicker.saveFile(
          fileName: report.fileName(format),
          bytes: bytes,
          mimeType: format.mimeType,
        );
        return path != null;
      };
    });

class TransactionHistoryPage extends ConsumerStatefulWidget {
  const TransactionHistoryPage({
    super.key,
    required this.initialType,
    this.initialDate,
    required this.transactionBuilder,
    required this.onAdd,
    required this.categoryIcon,
    required this.categoryColor,
  });
  final String? initialType;
  final DateTime? initialDate;
  final Widget Function(Transaction) transactionBuilder;
  final VoidCallback onAdd;
  final IconData Function(String) categoryIcon;
  final Color Function(String) categoryColor;

  @override
  ConsumerState<TransactionHistoryPage> createState() =>
      _TransactionHistoryPageState();
}

class _TransactionHistoryPageState
    extends ConsumerState<TransactionHistoryPage> {
  late TransactionFilters _filters;
  late DateTime _date;
  TransactionPeriod _period = TransactionPeriod.monthly;
  bool _exporting = false;
  @override
  void initState() {
    super.initState();
    _filters = TransactionFilters(type: widget.initialType);
    final now = widget.initialDate ?? DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void didUpdateWidget(covariant TransactionHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate != oldWidget.initialDate &&
        widget.initialDate != null) {
      _date = widget.initialDate!;
      _period = TransactionPeriod.monthly;
    }
    if (widget.initialType != oldWidget.initialType) {
      _filters = TransactionFilters(
        type: widget.initialType,
        accountId: _filters.accountId,
        categoryName: _filters.categoryName,
      );
    }
  }

  List<Transaction> _visible(List<Transaction> all, List<Category> categories) {
    final names = {
      for (final category in categories) category.id: category.name,
    };
    return all
        .where(
          (t) => _filters.matches(
            ledgerTransaction(t),
            month: _date,
            period: _period,
            categoryNames: names,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byDate = b.occurredAt.compareTo(a.occurredAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
  }

  Future<void> _openFilters(
    List<Account> accounts,
    List<Category> categories,
  ) async {
    final result = await showTransactionGlassDialog<TransactionFilters>(
      context,
      TransactionFilterDialog(
        initial: _filters,
        accounts: accounts,
        categories: categories,
        categoryIcon: widget.categoryIcon,
        categoryColor: widget.categoryColor,
      ),
    );
    if (mounted && result != null) setState(() => _filters = result);
  }

  Future<void> _choosePeriod() async {
    final result = await showTransactionGlassDialog<TransactionPeriod>(
      context,
      _PeriodSelectionDialog(initial: _period),
    );
    if (mounted && result != null) setState(() => _period = result);
  }

  Future<void> _export(
    List<Transaction> items,
    List<Account> accounts,
    List<Category> categories,
    FinanceReportFormat format,
  ) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final saved = await ref.read(transactionReportExportProvider)(
        TransactionReport(
          transactions: items,
          accounts: accounts,
          categories: categories,
          date: _date,
          period: _period,
        ),
        format,
      );
      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Laporan ${format.extension.toUpperCase()} berhasil disimpan.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Laporan belum dapat disimpan. Coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider);
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);
    final ready =
        transactions.hasValue && accounts.hasValue && categories.hasValue;
    final items = _visible(
      transactions.asData?.value ?? [],
      categories.asData?.value ?? [],
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTheme.pagePadding),
              child: _TransactionToolbar(
                active: _filters.isActive,
                exporting: _exporting,
                onFilter: ready
                    ? () => _openFilters(
                        accounts.requireValue,
                        categories.requireValue,
                      )
                    : null,
                onCalendar: _choosePeriod,
                onExport: ready && items.isNotEmpty && !_exporting
                    ? (format) => _export(
                        items,
                        accounts.requireValue,
                        categories.requireValue,
                        format,
                      )
                    : null,
              ),
            ),
            Expanded(
              child: transactions.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _loadError(
                  'Transaksi',
                  () => ref.invalidate(transactionsProvider),
                ),
                data: (_) => accounts.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _loadError(
                    'Akun',
                    () => ref.invalidate(accountsProvider),
                  ),
                  data: (_) => categories.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => _loadError(
                      'Kategori',
                      () => ref.invalidate(categoriesProvider),
                    ),
                    data: (_) => _history(items),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          MediaQuery.sizeOf(context).width >= AppTheme.sidebarBreakpoint
          ? null
          : FloatingActionButton(
              onPressed: widget.onAdd,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _loadError(String label, VoidCallback retry) => EmptyState(
    title: '$label gagal dimuat',
    message: 'Data lokal belum dapat dibaca. Coba muat ulang.',
    actionLabel: 'Coba lagi',
    onAction: retry,
  );

  Widget _history(List<Transaction> items) {
    int total(String type) =>
        items.where((t) => t.type == type).fold(0, (sum, t) => sum + t.amount);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
          sliver: SliverToBoxAdapter(
            child: _TransactionPeriodSummary(
              date: _date,
              period: _period,
              income: total('income'),
              expense: total('expense'),
              previous: () => setState(() => _date = _period.shift(_date, -1)),
              next: () => setState(() => _date = _period.shift(_date, 1)),
            ),
          ),
        ),
        if (_filters.isActive)
          SliverPadding(
            padding: const EdgeInsets.all(AppTheme.pagePadding),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: AppTheme.compactSpacing,
                runSpacing: AppTheme.compactSpacing,
                children: [
                  if (_filters.type != null)
                    _filterChip(switch (_filters.type) {
                      'income' => 'Pemasukan',
                      'expense' => 'Pengeluaran',
                      _ => 'Transfer',
                    }),
                  if (_filters.categoryName != null)
                    _filterChip(_filters.categoryName!),
                  if (_filters.accountId != null)
                    _filterChip(
                      ref
                              .read(accountsProvider)
                              .requireValue
                              .where((a) => a.id == _filters.accountId)
                              .firstOrNull
                              ?.name ??
                          'Akun',
                    ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _filters = const TransactionFilters()),
                    child: const Text('Hapus filter'),
                  ),
                ],
              ),
            ),
          ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: _filters.isActive
                  ? 'Tidak ada transaksi yang cocok'
                  : 'Belum ada transaksi pada periode ini',
              message: _filters.isActive
                  ? 'Ubah filter atau pilih periode lain.'
                  : 'Pilih periode lain atau mulai mencatat transaksi.',
              actionLabel: _filters.isActive
                  ? 'Hapus filter'
                  : 'Tambah transaksi',
              onAction: _filters.isActive
                  ? () => setState(() => _filters = const TransactionFilters())
                  : widget.onAdd,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(
              bottom: AppTheme.floatingBottomSpace,
            ),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final day = item.occurredAt.toLocal();
                final previous = index == 0
                    ? null
                    : items[index - 1].occurredAt.toLocal();
                final newDate =
                    previous == null ||
                    previous.year != day.year ||
                    previous.month != day.month ||
                    previous.day != day.day;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (newDate)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.pagePadding,
                          AppTheme.fieldSpacing,
                          AppTheme.pagePadding,
                          AppTheme.compactSpacing,
                        ),
                        child: Text(
                          formatShortDate(item.occurredAt),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Theme.of(context).colorScheme.error,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.all(AppTheme.sectionSpacing),
                        child: const Icon(Icons.delete),
                      ),
                      onDismissed: (_) async {
                        await ref
                            .read(transactionActionsProvider)
                            .archive(item.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Transaksi dihapus'),
                              action: SnackBarAction(
                                label: 'Urungkan',
                                onPressed: () => ref
                                    .read(transactionActionsProvider)
                                    .restore(item.id),
                              ),
                            ),
                          );
                        }
                      },
                      child: widget.transactionBuilder(item),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _filterChip(String text) =>
      Chip(label: Text(text), avatar: const Icon(Icons.filter_alt_outlined));
}

class _TransactionToolbar extends StatelessWidget {
  const _TransactionToolbar({
    required this.active,
    required this.exporting,
    required this.onFilter,
    required this.onCalendar,
    required this.onExport,
  });
  final bool active, exporting;
  final VoidCallback? onFilter;
  final ValueChanged<FinanceReportFormat>? onExport;
  final VoidCallback onCalendar;
  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppTheme.sidebarBreakpoint;
    final title = Row(
      children: [
        if (compact) ...[
          const ProfileMenu.compact(),
          const SizedBox(width: AppTheme.compactSpacing),
        ],
        Expanded(
          child: Text('Transaksi', style: AppTheme.pageTitleStyle(context)),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('transaction-filter-button'),
          style: _actionStyle(context),
          tooltip: 'Filter transaksi',
          onPressed: onFilter,
          isSelected: active,
          icon: const TransactionToolbarIcon(
            symbol: TransactionToolbarSymbol.filter,
          ),
        ),
        IconButton(
          key: const ValueKey('transaction-calendar-button'),
          style: _actionStyle(context),
          tooltip: 'Pilih periode',
          onPressed: onCalendar,
          icon: const Icon(
            Icons.calendar_month_outlined,
            size: AppTheme.transactionIconSize,
          ),
        ),
        Builder(
          builder: (anchorContext) => IconButton(
            key: const ValueKey('transaction-export-button'),
            style: _actionStyle(context),
            tooltip: 'Unduh laporan keuangan',
            onPressed: onExport == null
                ? null
                : () async {
                    final selected = await showTransactionReportDownloadMenu(
                      context: context,
                      anchorContext: anchorContext,
                    );
                    if (context.mounted && selected != null) {
                      onExport!(selected);
                    }
                  },
            icon: exporting
                ? const SizedBox.square(
                    dimension: AppTheme.transactionIconSize,
                    child: CircularProgressIndicator(),
                  )
                : const TransactionToolbarIcon(
                    symbol: TransactionToolbarSymbol.download,
                  ),
          ),
        ),
      ],
    );
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.primary),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final needed =
              MediaQuery.textScalerOf(context).scale(180) +
              (compact
                  ? AppTheme.minTouchTarget + AppTheme.compactSpacing
                  : 0) +
              AppTheme.minTouchTarget * 3;
          if (constraints.maxWidth < needed) {
            return Column(
              children: [
                title,
                const SizedBox(height: AppTheme.compactSpacing),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              actions,
            ],
          );
        },
      ),
    );
  }

  ButtonStyle _actionStyle(BuildContext context) => IconButton.styleFrom(
    foregroundColor: Theme.of(context).colorScheme.primary,
    disabledForegroundColor: AppTheme.mutedText,
    minimumSize: const Size.square(AppTheme.minTouchTarget),
  );
}

class _TransactionPeriodSummary extends StatelessWidget {
  const _TransactionPeriodSummary({
    required this.date,
    required this.period,
    required this.income,
    required this.expense,
    required this.previous,
    required this.next,
  });
  final DateTime date;
  final TransactionPeriod period;
  final int income, expense;
  final VoidCallback previous, next;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.transactionSummaryFill,
        borderRadius: BorderRadius.circular(AppTheme.panelRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.menuRowPadding),
        child: Row(
          children: [
            IconButton(
              tooltip: '${period.unit} sebelumnya',
              onPressed: previous,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    period.title(date),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppTheme.fieldSpacing),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final metrics = [
                        _metric(
                          context,
                          'Pemasukan',
                          income,
                          AppTheme.transactionIncome,
                        ),
                        _metric(
                          context,
                          'Pengeluaran',
                          expense,
                          AppTheme.transactionExpense,
                        ),
                      ];
                      if (constraints.maxWidth <
                          MediaQuery.textScalerOf(context).scale(280)) {
                        return Column(
                          children: [
                            metrics.first,
                            const SizedBox(height: AppTheme.fieldSpacing),
                            metrics.last,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          for (final metric in metrics) Expanded(child: metric),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '${period.unit} berikutnya',
              onPressed: next,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _metric(BuildContext context, String label, int amount, Color color) =>
      Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.compactSpacing),
          Text(
            formatRupiah(amount),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: color),
          ),
        ],
      );
}

class _PeriodSelectionDialog extends StatelessWidget {
  const _PeriodSelectionDialog({required this.initial});
  final TransactionPeriod initial;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pilih periode',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Tutup kalender',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.fieldSpacing),
        for (final period in TransactionPeriod.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.compactSpacing),
            child: OutlinedButton(
              key: ValueKey('transaction-period-${period.name}'),
              style: OutlinedButton.styleFrom(
                backgroundColor: initial == period
                    ? AppTheme.sidebarSelectedFill
                    : null,
                padding: const EdgeInsets.all(AppTheme.fieldSpacing),
              ),
              onPressed: () => Navigator.pop(context, period),
              child: Text(period.label, textAlign: TextAlign.center),
            ),
          ),
      ],
    ),
  );
}
