import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/mvp_screens.dart'
    show showTransactionEditor, ledgyCategoryIcon, ledgyCategoryColor;
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/profile_menu.dart';
import '../../sync/presentation/sync_providers.dart' show cloudUserProvider;
import '../../local/data/local_finance_repository.dart';
import '../../local/presentation/local_providers.dart';
import '../../reports/domain/finance_report.dart' show categoryParent;
import '../../quick_input/presentation/quick_input_bar.dart';
import '../domain/dashboard_summary.dart';
import 'dashboard_widgets.dart';
import 'savings_goals_panel.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _search = TextEditingController();
  CashflowPeriod _chartPeriod = CashflowPeriod.weekly;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _transactions([String? type]) => context.go(
    Uri(
      path: '/transactions',
      queryParameters: {'month': _month.toIso8601String(), 'type': ?type},
    ).toString(),
  );

  void _openBudgets() => context.go(
    Uri(
      path: '/budget',
      queryParameters: {'month': _month.toIso8601String()},
    ).toString(),
  );

  String get _greeting => switch (DateTime.now().hour) {
    < 11 => 'Selamat pagi',
    < 15 => 'Selamat siang',
    < 18 => 'Selamat sore',
    _ => 'Selamat malam',
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(financeSnapshotProvider);
    return QuickInputShortcutScope(
      child: Scaffold(
        appBar: MediaQuery.sizeOf(context).width < AppTheme.sidebarBreakpoint
            ? AppBar(
                title: const Text('Dashboard'),
                leading: const ProfileMenu.compact(),
              )
            : null,
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => EmptyState(
            title: 'Dashboard belum dapat dimuat',
            message: 'Coba muat ulang data keuanganmu.',
            actionLabel: 'Coba lagi',
            onAction: () => ref.invalidate(financeSnapshotProvider),
          ),
          data: (snapshot) => _content(snapshot),
        ),
      ),
    );
  }

  Widget _content(FinanceSnapshot snapshot) {
    final summary = DashboardSummary(snapshot, _month);
    final user = ref.watch(cloudUserProvider).asData?.value;
    final cashflow = summary.cashflow;
    final ratio = summary.savingsRatio;
    final budgets = summary.budgets;
    final alerts = budgets
        .where((b) => b.budget.amount > 0 && b.spent >= b.budget.amount * .8)
        .toList();
    final due = snapshot.rules
        .where(
          (r) =>
              r.deletedAt == null &&
              r.isActive &&
              !r.nextOccurrenceAt.isAfter(DateTime.now().toUtc()),
        )
        .toList();
    final points = summary.trend(_chartPeriod);
    final recent = summary.recent(_search.text);
    final period = DateFormat('MMM', 'id_ID').format(_month);
    final metrics = [
      DashboardMetric(
        title: 'Kekayaan Bersih',
        value: formatRupiah(summary.netWorth),
        detail: 'Saldo seluruh aset saat ini',
        icon: Icons.account_balance_wallet_outlined,
        color: dashboardIncome,
        onTap: () => context.go('/accounts'),
      ),
      DashboardMetric(
        title: 'Pemasukan ($period)',
        value: formatRupiah(cashflow.income),
        detail: 'Lihat transaksi pemasukan',
        icon: Icons.trending_up,
        color: dashboardIncome,
        onTap: () => _transactions('income'),
      ),
      DashboardMetric(
        title: 'Pengeluaran ($period)',
        value: formatRupiah(cashflow.expense),
        detail: 'Sisa ${formatRupiah(cashflow.net)}',
        icon: Icons.trending_down,
        color: dashboardExpense,
        onTap: () => _transactions('expense'),
      ),
      DashboardMetric(
        title: 'Rasio Tabungan',
        value: ratio == null
            ? '—'
            : '${NumberFormat('0.#', 'id_ID').format(ratio * 100)}%',
        detail: ratio == null
            ? 'Belum ada pemasukan bulan ini'
            : ratio < 0
            ? 'Pengeluaran melebihi pemasukan'
            : 'Porsi pemasukan yang tersisa',
        icon: Icons.savings_outlined,
        color: dashboardIncome,
        ratio: ratio ?? 0,
      ),
    ];
    return SingleChildScrollView(
      key: const ValueKey('dashboard-scroll'),
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final width = constraints.maxWidth;
              final columns = width >= 1050 * scale
                  ? 4
                  : width >= 550 * scale
                  ? 2
                  : 1;
              final twoPanels = width >= 850 * scale;
              final chart = DashboardPanel(
                title: 'Tren Arus Kas',
                action: PopupMenuButton<CashflowPeriod>(
                  tooltip: 'Periode grafik arus kas',
                  initialValue: _chartPeriod,
                  onSelected: (value) => setState(() => _chartPeriod = value),
                  itemBuilder: (_) => [
                    for (final period in CashflowPeriod.values)
                      PopupMenuItem(value: period, child: Text(period.label)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _chartPeriod.label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                ),
                child: DashboardCashflowChart(
                  points: points,
                  period: _chartPeriod,
                ),
              );
              final budgetPanel = _budgets(budgets);
              final transactionPanel = _recent(recent, snapshot);
              final goals = const SavingsGoalsPanel();
              final panelWidth = twoPanels
                  ? (width - AppTheme.fieldSpacing) / 2
                  : width;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: width >= 1050 * scale ? width - 530 : width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    '$_greeting${user == null ? '!' : ', ${user.displayName}!'}',
                                    style: AppTheme.pageTitleStyle(context),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.waving_hand_rounded,
                                  color: dashboardExpense,
                                  size: 22,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Pantau keuanganmu dalam satu tempat.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.mutedText),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: width < 500 ? width : 240,
                        child: TextField(
                          controller: _search,
                          key: const ValueKey('dashboard-search'),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Cari transaksi…',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Hapus pencarian',
                                    onPressed: () => setState(_search.clear),
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Notifikasi keuangan',
                        onPressed: () => _notifications(alerts, due.length),
                        icon: Badge(
                          isLabelVisible: alerts.isNotEmpty || due.isNotEmpty,
                          child: const Icon(Icons.notifications_none_rounded),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => showTransactionEditor(context),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Transaksi Baru'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.fieldSpacing),
                  const DashboardQuickInput(),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        key: const ValueKey('dashboard-previous-month'),
                        tooltip: 'Bulan sebelumnya',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(
                          () =>
                              _month = DateTime(_month.year, _month.month - 1),
                        ),
                      ),
                      Text(
                        DateFormat('MMMM yyyy', 'id_ID').format(_month),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        key: const ValueKey('dashboard-next-month'),
                        tooltip: 'Bulan berikutnya',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(
                          () =>
                              _month = DateTime(_month.year, _month.month + 1),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          final now = DateTime.now();
                          _month = DateTime(now.year, now.month);
                        }),
                        child: const Text('Bulan ini'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final metric in metrics)
                        SizedBox(
                          width: (width - 16 * (columns - 1)) / columns,
                          child: metric,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: AppTheme.fieldSpacing,
                    runSpacing: AppTheme.fieldSpacing,
                    children: [
                      for (final panel in [
                        chart,
                        budgetPanel,
                        transactionPanel,
                        goals,
                        _assets(summary),
                      ])
                        SizedBox(width: panelWidth, child: panel),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _budgets(List<BudgetProgress> budgets) => DashboardPanel(
    title: 'Alokasi & Kinerja Anggaran',
    action: IconButton(
      tooltip: 'Lihat semua anggaran',
      onPressed: _openBudgets,
      icon: const Icon(Icons.arrow_outward, size: 20),
    ),
    child: budgets.isEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Atur batas pengeluaran untuk setiap kategori.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openBudgets,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Kelola anggaran'),
              ),
            ],
          )
        : Column(
            children: [
              for (final b in budgets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: _openBudgets,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _categoryBadge(b.category),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  categoryParent(b.category),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${formatRupiah(b.spent)} / ${formatRupiah(b.budget.amount)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.mutedText),
                                ),
                                const SizedBox(height: 10),
                                DashboardProgress(
                                  value: b.budget.amount <= 0
                                      ? 0
                                      : b.spent / b.budget.amount,
                                  color: b.spent >= b.budget.amount
                                      ? AppTheme.transactionExpense
                                      : b.spent >= b.budget.amount * .8
                                      ? dashboardExpense
                                      : ledgyCategoryColor(b.category),
                                ),
                                if (b.spent >= b.budget.amount) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Batas anggaran tercapai',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppTheme.transactionExpense,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );

  Widget _recent(List<Transaction> transactions, FinanceSnapshot snapshot) {
    final query = _search.text.trim();
    final names = {for (final a in snapshot.accounts) a.id: a.name};
    final visible = transactions;
    return DashboardPanel(
      title: query.isEmpty ? 'Transaksi Terakhir' : 'Hasil Pencarian',
      action: IconButton(
        tooltip: 'Lihat semua transaksi',
        onPressed: _transactions,
        icon: const Icon(Icons.arrow_outward, size: 20),
      ),
      child: transactions.isEmpty
          ? Text(
              query.isEmpty
                  ? 'Belum ada transaksi pada bulan ini.'
                  : 'Tidak ada transaksi yang cocok dengan "$query".',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (query.isNotEmpty) ...[
                  Text(
                    '${transactions.length} transaksi ditemukan di seluruh periode.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                for (final t in visible) ...[
                  InkWell(
                    onTap: () => _showTransaction(t, snapshot),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final category =
                              snapshot.categoryNames[t.categoryId] ??
                              (t.type == 'transfer'
                                  ? 'Transfer'
                                  : t.type == 'income'
                                  ? 'Pemasukan'
                                  : 'Pengeluaran');
                          final amount = Text(
                            '${t.type == 'income'
                                ? '+'
                                : t.type == 'expense'
                                ? '−'
                                : ''}${formatRupiah(t.amount)}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: t.type == 'income'
                                      ? dashboardIncome
                                      : t.type == 'expense'
                                      ? AppTheme.transactionExpense
                                      : AppTheme.mutedText,
                                  fontWeight: FontWeight.w600,
                                ),
                          );
                          final stacked =
                              constraints.maxWidth < 450 ||
                              MediaQuery.textScalerOf(context).scale(14) > 18;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _categoryBadge(category, type: t.type),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.note?.trim().isNotEmpty == true
                                          ? t.note!
                                          : category,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${DateFormat('d MMM • HH.mm', 'id_ID').format(t.occurredAt.toLocal())} · ${names[t.accountId] ?? 'Aset'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppTheme.mutedText),
                                    ),
                                    if (stacked) ...[
                                      const SizedBox(height: 6),
                                      amount,
                                    ],
                                  ],
                                ),
                              ),
                              if (!stacked) ...[
                                const SizedBox(width: 12),
                                amount,
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  if (t != visible.last)
                    const Divider(height: 1, color: AppTheme.sidebarBorder),
                ],
              ],
            ),
    );
  }

  Widget _categoryBadge(String category, {String? type}) {
    final color = type == 'income'
        ? dashboardIncome
        : type == 'transfer'
        ? Theme.of(context).colorScheme.primary
        : ledgyCategoryColor(category);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .17),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        type == 'transfer' ? Icons.swap_horiz : ledgyCategoryIcon(category),
        size: 18,
        color: color,
      ),
    );
  }

  Widget _assets(DashboardSummary summary) => DashboardPanel(
    title: 'Aset Saya',
    action: IconButton(
      tooltip: 'Kelola aset',
      onPressed: () => context.go('/accounts'),
      icon: const Icon(Icons.arrow_outward, size: 20),
    ),
    child: summary.accounts.isEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tambahkan aset untuk mencatat saldo awal.'),
              const SizedBox(height: AppTheme.fieldSpacing),
              OutlinedButton.icon(
                onPressed: () => context.go('/asset-setup'),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Tambahkan aset pertama'),
              ),
            ],
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final columns = constraints.maxWidth >= 900 * scale
                  ? 3
                  : constraints.maxWidth >= 530 * scale
                  ? 2
                  : 1;
              final balances = summary.balances;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final a in summary.accounts)
                    SizedBox(
                      width:
                          (constraints.maxWidth - 12 * (columns - 1)) / columns,
                      child: Material(
                        color: Colors.white.withValues(alpha: .04),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => context.go('/assets/${a.id}'),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        a.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  formatRupiah(balances[a.id] ?? 0),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
  );

  void _showTransaction(Transaction transaction, FinanceSnapshot snapshot) {
    final names = {for (final a in snapshot.accounts) a.id: a.name};
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          transaction.note?.trim().isNotEmpty == true
              ? transaction.note!
              : snapshot.categoryNames[transaction.categoryId] ?? 'Transaksi',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatRupiah(transaction.amount),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                DateFormat(
                  'd MMMM yyyy • HH.mm',
                  'id_ID',
                ).format(transaction.occurredAt.toLocal()),
              ),
              const SizedBox(height: 8),
              Text(names[transaction.accountId] ?? 'Aset diarsipkan'),
              if (transaction.recipientName != null) ...[
                Text('Penerima: ${transaction.recipientName}'),
                Text('Rekening: ${transaction.recipientAccount}'),
              ] else if (transaction.type == 'transfer')
                Text(
                  'Ke ${names[transaction.toAccountId] ?? 'aset diarsipkan'}',
                ),
              if (transaction.categoryId != null) ...[
                const SizedBox(height: 8),
                Text(
                  snapshot.categoryNames[transaction.categoryId] ?? 'Lainnya',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              this.context.go(
                Uri(
                  path: '/transactions',
                  queryParameters: {
                    'month': transaction.occurredAt.toLocal().toIso8601String(),
                    'type': transaction.type,
                  },
                ).toString(),
              );
            },
            child: const Text('Lihat transaksi'),
          ),
        ],
      ),
    );
  }

  void _notifications(List<BudgetProgress> alerts, int due) => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Notifikasi Keuangan'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (alerts.isEmpty && due == 0)
                const Text('Semua terkendali. Belum ada pengingat keuangan.'),
              for (final b in alerts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: dashboardExpense,
                  ),
                  title: Text(b.category),
                  subtitle: Text(
                    '${formatRupiah(b.spent)} dari ${formatRupiah(b.budget.amount)} terpakai.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openBudgets();
                  },
                ),
              if (due > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.autorenew),
                  title: Text('$due transaksi berulang jatuh tempo'),
                  onTap: () {
                    Navigator.pop(context);
                    this.context.go('/budget?section=recurring');
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}
