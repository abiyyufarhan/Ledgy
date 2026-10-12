import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../features/quick_input/presentation/receipt_attachment_action.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/database/app_database.dart';
import '../core/providers/app_providers.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/currency_formatter.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/glass_dropdown_field.dart';
import '../core/widgets/glass_menu.dart';
import '../core/widgets/transaction_form_surface.dart';
import '../features/auth/presentation/profile_menu.dart';
import '../features/categories/domain/category_catalog.dart';
import '../features/quick_input/domain/draft_validator.dart';
import '../features/quick_input/domain/transaction_draft.dart';
import '../features/quick_input/presentation/quick_input_providers.dart';
import '../features/transactions/presentation/transaction_history_page.dart';
import '../features/transactions/domain/usecases/calculate_balance_history.dart';

export '../features/dashboard/presentation/dashboard_page.dart';

final _amountInputFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return const TextEditingValue();

  final amount = int.tryParse(digits);
  if (amount == null) return oldValue;

  final formatted = NumberFormat.decimalPattern('id_ID').format(amount);
  return TextEditingValue(
    text: formatted,
    selection: TextSelection.collapsed(offset: formatted.length),
  );
});

String? _validTransactionType(String? type) => switch (type) {
  'income' || 'expense' || 'transfer' => type,
  _ => null,
};

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  late final PageController _pageController;
  final _name = TextEditingController();
  final _balance = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: PageView(
          physics: const NeverScrollableScrollPhysics(),
          controller: _pageController,
          children: [
            _Welcome(onStart: _nextPage),
            _OnboardingValue(onContinue: _nextPage),
            _FirstAccount(
              name: _name,
              balance: _balance,
              onSave: () async {
                if (_name.text.trim().isEmpty) return;
                await ref
                    .read(accountActionsProvider)
                    .save(
                      name: _name.text,
                      initialBalance: int.tryParse(_balance.text) ?? 0,
                    );
                if (context.mounted) context.go('/');
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _OnboardingValue extends StatelessWidget {
  const _OnboardingValue({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 68),
        const SizedBox(height: 24),
        Text(
          'Catat dengan tenang',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Data tersimpan lokal di perangkatmu dan siap dicadangkan saat kamu membutuhkannya.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        FilledButton(onPressed: onContinue, child: const Text('Lanjut')),
      ],
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart});
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.auto_graph_rounded, size: 84),
        const SizedBox(height: 24),
        Text('Ledgy', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        const Text(
          'Keuangan pribadi, tetap milikmu.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Mulai'),
        ),
      ],
    ),
  );
}

class _FirstAccount extends StatelessWidget {
  const _FirstAccount({
    required this.name,
    required this.balance,
    required this.onSave,
  });
  final TextEditingController name, balance;
  final VoidCallback onSave;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buat akun pertama',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Mulai dari rekening atau dompet yang paling sering kamu pakai.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nama akun',
              hintText: 'Contoh: BCA atau Tunai',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: balance,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Saldo awal (Rp)'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSave,
              child: const Text('Simpan dan lanjutkan'),
            ),
          ),
        ],
      ),
    ),
  );
}

List<DailyBalance> _balanceHistory({
  required List<Account> accounts,
  required List<Transaction> transactions,
  required String? accountId,
  bool calendarMonth = false,
  DateTime? now,
}) {
  final localNow = (now ?? DateTime.now()).toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final start = today.subtract(const Duration(days: 29));
  final changes = <BalanceChange>[];

  final includedAccountIds = accountId == null
      ? accounts.map((account) => account.id).toSet()
      : {accountId};
  bool includes(String id) => includedAccountIds.contains(id);
  void addChange(DateTime moment, int amount) {
    changes.add(BalanceChange(occurredAt: moment, amount: amount));
  }

  for (final account in accounts.where((account) => includes(account.id))) {
    addChange(account.createdAt, account.initialBalance);
  }
  for (final transaction in transactions) {
    var change = 0;
    if (transaction.type == 'income' && includes(transaction.accountId)) {
      change += transaction.amount;
    } else if (transaction.type == 'expense' &&
        includes(transaction.accountId)) {
      change -= transaction.amount;
    } else if (transaction.type == 'transfer') {
      if (includes(transaction.accountId)) change -= transaction.amount;
      if (transaction.toAccountId != null &&
          includes(transaction.toAccountId!)) {
        change += transaction.amount;
      }
    }
    if (change != 0) addChange(transaction.occurredAt, change);
  }

  if (calendarMonth) {
    return BalanceHistoryCalculator.currentMonth(
      now: localNow,
      changes: changes,
    );
  }
  return BalanceHistoryCalculator.calculate(
    startDate: start,
    endDate: today,
    changes: changes,
  );
}

Map<String, int> _currentBalances({
  required List<Account> accounts,
  required List<Transaction> transactions,
}) {
  final activeIds = accounts.map((account) => account.id).toSet();
  final balances = {
    for (final account in accounts) account.id: account.initialBalance,
  };
  void apply(String accountId, int amount) {
    if (!activeIds.contains(accountId)) return;
    balances[accountId] = (balances[accountId] ?? 0) + amount;
  }

  for (final transaction in transactions) {
    switch (transaction.type) {
      case 'income':
        apply(transaction.accountId, transaction.amount);
        break;
      case 'expense':
        apply(transaction.accountId, -transaction.amount);
        break;
      case 'transfer':
        apply(transaction.accountId, -transaction.amount);
        if (transaction.toAccountId != null) {
          apply(transaction.toAccountId!, transaction.amount);
        }
        break;
    }
  }
  return balances;
}

class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key, this.initialType, this.initialDate});

  final String? initialType;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context) => TransactionHistoryPage(
    initialType: _validTransactionType(initialType),
    initialDate: initialDate,
    transactionBuilder: (transaction) =>
        _TransactionTile(transaction: transaction),
    onAdd: () => showTransactionEditor(context),
    categoryIcon: ledgyCategoryIcon,
    categoryColor: ledgyCategoryColor,
  );
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({required this.transaction});
  final Transaction transaction;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sign = transaction.type == 'income'
        ? '+'
        : transaction.type == 'expense'
        ? '-'
        : '↔';
    final categories =
        ref.watch(categoriesProvider).asData?.value ?? const <Category>[];
    final category = categories
        .where((item) => item.id == transaction.categoryId)
        .firstOrNull;
    final categoryLabel =
        category?.name ??
        (transaction.type == 'transfer'
            ? transaction.recipientName != null
                  ? 'Transfer ke penerima'
                  : 'Transfer antar aset'
            : 'Belum dikategorikan');
    final categoryParts = categoryLabel
        .split('•')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final categoryParent = categoryParts.firstOrNull ?? categoryLabel;
    final subcategoryLabel = categoryParts.length > 1
        ? categoryParts.skip(1).join(' • ')
        : categoryParent;
    final categoryVisual = _categoryVisual(categoryParent);
    return ListTile(
      leading: CircleAvatar(
        child: Icon(
          transaction.type == 'transfer'
              ? Icons.swap_horiz
              : transaction.type == 'income'
              ? Icons.south_west
              : Icons.north_east,
        ),
      ),
      title: Text(
        transaction.note?.isNotEmpty == true
            ? transaction.note!
            : transaction.type == 'income'
            ? 'Pemasukan'
            : transaction.type == 'expense'
            ? 'Pengeluaran'
            : transaction.recipientName != null
            ? 'Transfer ke ${transaction.recipientName}'
            : 'Transfer',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              formatTransactionDateTime(transaction.occurredAt),
              if (transaction.recipientName != null)
                '${transaction.recipientName} • ${transaction.recipientAccount}',
            ].join('\n'),
          ),
          ReceiptAttachmentAction(transactionId: transaction.id),
        ],
      ),
      trailing: SizedBox(
        width: 164,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign${formatRupiah(transaction.amount)}',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  categoryVisual.icon,
                  size: 16,
                  color: categoryVisual.color,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    subcategoryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: Colors.white.withValues(alpha: .72)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(accountsProvider);
    final transactions = ref.watch(transactionsProvider).asData?.value ?? [];
    void addAsset() => context.go('/asset-setup');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Aset'),
        leading: MediaQuery.sizeOf(context).width < AppTheme.sidebarBreakpoint
            ? const ProfileMenu.compact()
            : null,
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          title: 'Data tidak dapat dimuat',
          message: 'Aset lokal belum dapat dibaca. Coba muat ulang.',
          actionLabel: 'Coba lagi',
          onAction: () => ref.invalidate(accountsProvider),
        ),
        data: (assets) {
          if (assets.isEmpty) {
            return EmptyState(
              title: 'Belum ada aset',
              message: 'Tambahkan aset pertama untuk mulai mencatat saldo.',
              actionLabel: 'Tambah aset',
              onAction: addAsset,
            );
          }
          final balances = _currentBalances(
            accounts: assets,
            transactions: transactions,
          );
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: assets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final asset = assets[index];
              return _AssetCard(
                asset: asset,
                balance: balances[asset.id] ?? 0,
                onOpen: () => context.push('/assets/${asset.id}'),
                onArchive: () async {
                  final confirmed = await _confirmAssetArchive(context);
                  if (confirmed && context.mounted) {
                    await ref.read(accountActionsProvider).archive(asset.id);
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addAsset,
        tooltip: 'Tambah aset',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.asset,
    required this.balance,
    required this.onOpen,
    required this.onArchive,
  });

  final Account asset;
  final int balance;
  final VoidCallback onOpen;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 500 ||
        MediaQuery.textScalerOf(context).scale(16) > 22) {
      return GlassCard(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: AppTheme.compactSpacing),
                Expanded(
                  child: Text(
                    asset.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus aset',
                  onPressed: onArchive,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Text(
              'Aset keuangan',
              style: TextStyle(color: AppTheme.mutedText),
            ),
            const SizedBox(height: AppTheme.fieldSpacing),
            Text(
              formatRupiah(balance),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }
    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      enableBackdropBlur: false,
      child: SizedBox(
        height: 112,
        child: Row(
          children: [
            Container(
              width: 154,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF527EFF), Color(0xFF0D315E)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -24,
                    top: -32,
                    child: Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 46,
                      color: Colors.white.withValues(alpha: .88),
                    ),
                  ),
                  const Positioned(
                    left: 14,
                    bottom: 12,
                    child: Text(
                      'LEDGY  •  ASET',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 6, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Aset keuangan',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: AppTheme.mutedText),
                    ),
                    const Spacer(),
                    Text(
                      formatRupiah(balance),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: IconButton(
                tooltip: 'Hapus aset',
                onPressed: onArchive,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF2B3B53),
                  foregroundColor: const Color(0xFFF5F8FF),
                  side: const BorderSide(color: Color(0xFF8DA8D1)),
                  shape: const CircleBorder(),
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 24,
                  color: Color(0xFFF5F8FF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AssetDetailPage extends ConsumerWidget {
  const AssetDetailPage({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(accountsProvider);
    final transactions = ref.watch(transactionsProvider).asData?.value ?? [];
    return assets.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: EmptyState(
          title: 'Aset tidak dapat dimuat',
          message: 'Aset lokal belum dapat dibaca. Coba muat ulang.',
          actionLabel: 'Coba lagi',
          onAction: () => ref.invalidate(accountsProvider),
        ),
      ),
      data: (allAssets) {
        final asset = allAssets.where((item) => item.id == assetId).firstOrNull;
        if (asset == null) {
          return const Scaffold(
            body: EmptyState(
              title: 'Aset tidak ditemukan',
              message: 'Aset ini mungkin sudah diarsipkan.',
            ),
          );
        }
        final assetTransactions = transactions
            .where(
              (transaction) =>
                  transaction.accountId == asset.id ||
                  transaction.toAccountId == asset.id,
            )
            .toList();
        final income = assetTransactions
            .where(
              (transaction) =>
                  transaction.type == 'income' &&
                  transaction.accountId == asset.id,
            )
            .fold(0, (total, transaction) => total + transaction.amount);
        final expense = assetTransactions
            .where(
              (transaction) =>
                  transaction.type == 'expense' &&
                  transaction.accountId == asset.id,
            )
            .fold(0, (total, transaction) => total + transaction.amount);
        final points = _balanceHistory(
          accounts: [asset],
          transactions: transactions,
          accountId: asset.id,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(asset.name),
            actions: [
              IconButton(
                tooltip: 'Ubah aset',
                onPressed: () => _showNameDialog(
                  context,
                  title: 'Ubah aset',
                  initial: asset.name,
                  onSave: (name) => ref
                      .read(accountActionsProvider)
                      .save(
                        id: asset.id,
                        name: name,
                        initialBalance: asset.initialBalance,
                      ),
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AssetPerformanceChart(points: points),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 520;
                  final incomeCard = _AggregateCard(
                    label: 'Agregat pemasukan',
                    amount: income,
                    icon: Icons.south_west_rounded,
                    color: const Color(0xFF4ADE80),
                  );
                  final expenseCard = _AggregateCard(
                    label: 'Agregat pengeluaran',
                    amount: expense,
                    icon: Icons.north_east_rounded,
                    color: const Color(0xFFFB7185),
                  );
                  if (!wide) {
                    return Column(
                      children: [
                        incomeCard,
                        const SizedBox(height: 12),
                        expenseCard,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: incomeCard),
                      const SizedBox(width: 12),
                      Expanded(child: expenseCard),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              Text(
                'Historis transaksi',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (assetTransactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Belum ada transaksi pada aset ini.'),
                  ),
                ),
              ...assetTransactions.map(
                (transaction) => _TransactionTile(transaction: transaction),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AssetPerformanceChart extends StatelessWidget {
  const _AssetPerformanceChart({required this.points});

  final List<DailyBalance> points;

  @override
  Widget build(BuildContext context) {
    final values = points.map((point) => point.balance.toDouble()).toList();
    final lowest = values.reduce(math.min);
    final highest = values.reduce(math.max);
    final difference = math.max(1.0, highest - lowest);
    final primary = Theme.of(context).colorScheme.primary;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kinerja keuangan',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 2),
          Text(
            '30 hari terakhir',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: AppTheme.mutedText),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: RepaintBoundary(
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (points.length - 1).toDouble(),
                  minY: lowest - difference * .18,
                  maxY: highest + difference * .18,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: difference / 2,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.white.withValues(alpha: .08)),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: 14,
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              DateFormat(
                                'd MMM',
                                'id_ID',
                              ).format(points[index].date),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((spot) {
                        final point = points[spot.x.round()];
                        return LineTooltipItem(
                          '${DateFormat('d MMM yyyy', 'id_ID').format(point.date)}\n${formatRupiah(point.balance)}',
                          const TextStyle(
                            color: Color(0xFFF5F8FF),
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var index = 0; index < points.length; index++)
                          FlSpot(
                            index.toDouble(),
                            points[index].balance.toDouble(),
                          ),
                      ],
                      isCurved: true,
                      curveSmoothness: .28,
                      color: primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            primary.withValues(alpha: .28),
                            primary.withValues(alpha: 0),
                          ],
                        ),
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
  }
}

class _AggregateCard extends StatelessWidget {
  const _AggregateCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final int amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => GlassCard(
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .16),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 3),
              Text(
                formatRupiah(amount),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<bool> _confirmAssetArchive(BuildContext context) async {
  final confirmation = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Hapus aset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Apakah Kamu Yakin untuk Menghapus Aset ini'),
            const SizedBox(height: 16),
            const Text('Ketik “Saya Yakin” untuk melanjutkan.'),
            const SizedBox(height: 10),
            TextField(
              controller: confirmation,
              autofocus: true,
              onChanged: (_) => setDialogState(() {}),
              decoration: const InputDecoration(hintText: 'Saya Yakin'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: confirmation.text == 'Saya Yakin'
                ? () => Navigator.pop(dialogContext, true)
                : null,
            child: const Text('Ya'),
          ),
        ],
      ),
    ),
  );
  confirmation.dispose();
  return result ?? false;
}

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(categoriesProvider);
    return _ManageList<Category>(
      title: 'Kelola kategori',
      data: data,
      nameOf: (item) => item.name,
      subtitleOf: (item) => item.kind == 'income' ? 'Pemasukan' : 'Pengeluaran',
      onAdd: () => _showNameDialog(
        context,
        title: 'Kategori baru',
        onSave: (name) =>
            ref.read(categoryActionsProvider).save(name: name, kind: 'expense'),
      ),
      onEdit: (item) => _showNameDialog(
        context,
        title: 'Ubah kategori',
        initial: item.name,
        onSave: (name) => ref
            .read(categoryActionsProvider)
            .save(id: item.id, name: name, kind: item.kind),
      ),
      onArchive: (item) => ref.read(categoryActionsProvider).archive(item.id),
    );
  }
}

class _ManageList<T> extends StatelessWidget {
  const _ManageList({
    required this.title,
    required this.data,
    required this.nameOf,
    required this.subtitleOf,
    required this.onAdd,
    required this.onEdit,
    required this.onArchive,
  });
  final String title;
  final AsyncValue<List<T>> data;
  final String Function(T) nameOf, subtitleOf;
  final VoidCallback onAdd;
  final Future<void> Function(T) onEdit, onArchive;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const EmptyState(
        title: 'Data tidak dapat dimuat',
        message: 'Data lokal belum dapat dibaca. Buka ulang aplikasi untuk mencoba lagi.',
      ),
      data: (items) => items.isEmpty
          ? EmptyState(
              title: 'Belum ada data',
              message: 'Tambahkan data baru untuk melanjutkan.',
              actionLabel: 'Tambah',
              onAction: onAdd,
            )
          : ListView(
              children: items
                  .map(
                    (item) => ListTile(
                      title: Text(nameOf(item)),
                      subtitle: Text(subtitleOf(item)),
                      onTap: () => onEdit(item),
                      trailing: IconButton(
                        onPressed: () => onArchive(item),
                        icon: const Icon(Icons.archive_outlined),
                      ),
                    ),
                  )
                  .toList(),
            ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: onAdd,
      child: const Icon(Icons.add),
    ),
  );
}

Future<void> _showNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  required Future<void> Function(String) onSave,
}) async {
  final controller = TextEditingController(text: initial);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Nama'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () async {
            if (controller.text.trim().isEmpty) return;
            await onSave(controller.text);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  controller.dispose();
}

class _CategoryVisual {
  const _CategoryVisual(this.icon, this.color);

  final IconData icon;
  final Color color;
}

Color ledgyCategoryColor(String name) => _categoryVisual(name).color;
IconData ledgyCategoryIcon(String name) => _categoryVisual(name).icon;

_CategoryVisual _categoryVisual(String categoryName) {
  final name = categoryName.split('•').first.trim().toLowerCase();
  if (name.startsWith('acara sosial')) {
    return const _CategoryVisual(Icons.chat_bubble_rounded, Color(0xFF347CF6));
  }
  if (name.startsWith('belanja')) {
    return const _CategoryVisual(
      Icons.shopping_basket_rounded,
      Color(0xFFA855F7),
    );
  }
  if (name.startsWith('cicilan')) {
    return const _CategoryVisual(
      Icons.account_balance_wallet_rounded,
      Color(0xFFB545C8),
    );
  }
  if (name.startsWith('hiburan')) {
    return const _CategoryVisual(
      Icons.movie_creation_rounded,
      Color(0xFFA855F7),
    );
  }
  if (name.startsWith('keluarga')) {
    return const _CategoryVisual(Icons.home_rounded, Color(0xFF38BDF8));
  }
  if (name.startsWith('kesehatan')) {
    return const _CategoryVisual(
      Icons.health_and_safety_rounded,
      Color(0xFF34D399),
    );
  }
  if (name.startsWith('makanan & minuman') ||
      name.startsWith('makan & minum') ||
      name == 'makanan') {
    return const _CategoryVisual(Icons.restaurant_rounded, Color(0xFFFBBF24));
  }
  if (name.startsWith('pembayaran pinjaman')) {
    return const _CategoryVisual(Icons.payments_rounded, Color(0xFF8677F9));
  }
  if (name.startsWith('pendidikan')) {
    return const _CategoryVisual(Icons.menu_book_rounded, Color(0xFF5B8CFF));
  }
  if (name.startsWith('tabungan')) {
    return const _CategoryVisual(Icons.savings_rounded, Color(0xFF34D399));
  }
  if (name.startsWith('tagihan')) {
    return const _CategoryVisual(Icons.receipt_long_rounded, Color(0xFFFF6B7A));
  }
  if (name.startsWith('top up')) {
    return const _CategoryVisual(Icons.add_card_rounded, Color(0xFF697DFF));
  }
  if (name.startsWith('transport')) {
    return const _CategoryVisual(
      Icons.directions_car_filled_rounded,
      Color(0xFF38BDF8),
    );
  }
  if (name == 'gaji' || name.startsWith('pemasukan')) {
    return const _CategoryVisual(Icons.south_west_rounded, Color(0xFF34D399));
  }
  return const _CategoryVisual(Icons.more_horiz_rounded, Color(0xFF8492A9));
}

Future<void> showTransactionEditor(
  BuildContext context, {
  String initialType = 'expense',
  TransactionDraft? initialDraft,
  TransactionDraft? originalDraft,
  ValueChanged<TransactionDraft>? onDraftSaved,
}) {
  final editor = TransactionEditor(
    initialType: initialType,
    initialDraft: initialDraft,
    originalDraft: originalDraft,
    onDraftSaved: onDraftSaved,
  );
  if (MediaQuery.sizeOf(context).width >= 700) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: editor,
        ),
      ),
    );
  } else {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: editor,
        ),
      ),
    );
  }
}

class TransactionEditor extends ConsumerStatefulWidget {
  const TransactionEditor({
    super.key,
    required this.initialType,
    this.initialDraft,
    this.originalDraft,
    this.onDraftSaved,
  });
  final String initialType;
  final TransactionDraft? initialDraft;
  final TransactionDraft? originalDraft;
  final ValueChanged<TransactionDraft>? onDraftSaved;
  @override
  ConsumerState<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends ConsumerState<TransactionEditor> {
  late String _type;
  String _amount = '';
  String? _account, _category, _toAccount;
  DateTime _date = DateTime.now();
  final _amountController = TextEditingController();
  final _note = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientAccount = TextEditingController();
  bool _saving = false;
  String? _saveError;

  bool get _draftTransfer =>
      widget.initialDraft != null &&
      _type == 'transfer' &&
      (widget.initialDraft!.toAccountId != null ||
          (widget.initialDraft!.recipientName == null &&
              widget.initialDraft!.recipientAccount == null));

  Future<void> _saveTransaction() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final original = widget.initialDraft;
      if (original != null) {
        final corrected = original.copyWith(
          type: TransactionType.values.byName(_type),
          amount: int.parse(_amount),
          accountId: _account,
          toAccountId: _draftTransfer ? _toAccount : null,
          recipientName: _type == 'transfer' && !_draftTransfer
              ? _recipientName.text.trim()
              : null,
          recipientAccount: _type == 'transfer' && !_draftTransfer
              ? _recipientAccount.text.trim()
              : null,
          categoryId: _type == 'transfer' ? null : _category,
          note: _note.text,
          occurredAt: _date,
        );
        final saved = await ref
            .read(quickInputActionsProvider)
            .save(
              original: widget.originalDraft ?? original,
              corrected: corrected,
            );
        widget.onDraftSaved?.call(saved);
      } else {
        await ref
            .read(transactionActionsProvider)
            .save(
              type: _type,
              amount: int.parse(_amount),
              accountId: _account!,
              recipientName: _type == 'transfer'
                  ? _recipientName.text.trim()
                  : null,
              recipientAccount: _type == 'transfer'
                  ? _recipientAccount.text.trim()
                  : null,
              categoryId: _type == 'transfer' ? null : _category,
              note: _note.text,
              occurredAt: _date,
            );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError = 'Transaksi belum tersimpan. Coba simpan kembali.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _type = draft?.type.name ?? widget.initialType;
    if (draft == null) return;
    _amount = draft.amount?.toString() ?? '';
    _amountController.text = draft.amount == null
        ? ''
        : NumberFormat.decimalPattern('id_ID').format(draft.amount);
    _account = draft.accountId;
    _toAccount = draft.toAccountId;
    _category = draft.categoryId;
    _date = draft.occurredAt?.toLocal() ?? DateTime.now();
    _note.text = draft.note ?? '';
    _recipientName.text = draft.recipientName ?? '';
    _recipientAccount.text = draft.recipientAccount ?? '';
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _date,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _date = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickCategory(List<Category> categories) async {
    final selected = await showLedgyCategoryPicker(
      context,
      type: _type,
      existingCategories: categories,
    );
    if (selected == null || !mounted) return;

    if (widget.initialDraft != null) {
      final choice = ref
          .read(quickInputCategoriesProvider)
          .choice(selected.databaseName, _type, categories);
      ref.invalidate(quickInputCategoryChoicesProvider);
      setState(() => _category = choice.id);
      return;
    }

    final existing = categories.where(
      (category) =>
          category.kind == _type &&
          (_type == 'income'
                  ? incomeCategoryName(category.name)
                  : category.name) ==
              selected.databaseName,
    );
    final id = existing.isNotEmpty ? existing.first.id : const Uuid().v4();
    if (existing.isEmpty) {
      await ref
          .read(categoryActionsProvider)
          .save(id: id, name: selected.databaseName, kind: _type);
    }
    if (mounted) setState(() => _category = id);
  }

  String? _selectedCategoryName(List<Category> categories) {
    for (final category in categories) {
      if (category.id == _category) {
        return _type == 'income'
            ? incomeCategoryName(category.name)
            : category.name;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _note.dispose();
    _recipientName.dispose();
    _recipientAccount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).asData?.value ?? [];
    final categories =
        (widget.initialDraft == null
                ? ref.watch(categoriesProvider)
                : ref.watch(quickInputCategoryChoicesProvider))
            .asData
            ?.value ??
        [];
    if (widget.initialDraft != null) {
      _category = ref
          .read(quickInputCategoriesProvider)
          .currentId(_category, categories);
    }
    if (widget.initialDraft == null) {
      _account ??= accounts.isEmpty ? null : accounts.first.id;
    }
    final draftInvalid =
        widget.initialDraft != null &&
        (const DraftValidator()
            .validate(
              widget.initialDraft!.copyWith(
                type: TransactionType.values.byName(_type),
                amount: int.tryParse(_amount),
                accountId: accounts.any((a) => a.id == _account)
                    ? _account
                    : null,
                toAccountId: accounts.any((a) => a.id == _toAccount)
                    ? _toAccount
                    : null,
                recipientName: _type == 'transfer' && !_draftTransfer
                    ? _recipientName.text.trim()
                    : null,
                recipientAccount: _type == 'transfer' && !_draftTransfer
                    ? _recipientAccount.text.trim()
                    : null,
                categoryId:
                    categories.any((c) => c.id == _category && c.kind == _type)
                    ? _category
                    : null,
                occurredAt: _date,
              ),
            )
            .isNotEmpty);
    final fieldHeight =
        AppTheme.transactionFieldHeight +
        (MediaQuery.textScalerOf(context).scale(16) - 16) * 2;
    final fieldDecoration = InputDecoration(
      constraints: BoxConstraints.tightFor(height: fieldHeight),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
    return TransactionFormSurface(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Transaksi Baru', style: AppTheme.pageTitleStyle(context)),
            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Keluar')),
                ButtonSegment(value: 'income', label: Text('Masuk')),
                ButtonSegment(value: 'transfer', label: Text('Transfer')),
              ],
              selected: {_type},
              onSelectionChanged: (value) => setState(() {
                _type = value.first;
                _category = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [_amountInputFormatter],
              textAlign: TextAlign.start,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: fieldDecoration.copyWith(
                labelText: 'Jumlah',
                prefixText: 'Rp ',
              ),
              onChanged: (value) =>
                  setState(() => _amount = value.replaceAll('.', '')),
            ),
            const SizedBox(height: 12),
            GlassDropdownFormField<String>(
              initialValue: _account,
              decoration: fieldDecoration.copyWith(
                labelText: _type == 'income' ? 'Menuju Akun' : 'Dari akun',
              ),
              items: accounts
                  .map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _account = value),
            ),
            if (_draftTransfer) ...[
              const SizedBox(height: AppTheme.fieldSpacing),
              GlassDropdownFormField<String>(
                initialValue: _toAccount,
                decoration: fieldDecoration.copyWith(labelText: 'Ke akun'),
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                ],
                onChanged: (value) => setState(() => _toAccount = value),
              ),
            ],
            if (_type == 'transfer' && !_draftTransfer) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _recipientName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: fieldDecoration.copyWith(
                        labelText: 'Nama Penerima',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _recipientAccount,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: fieldDecoration.copyWith(
                        labelText: 'Rekening Penerima',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],
            if (_type != 'transfer') ...[
              const SizedBox(height: 12),
              TransactionPickerField(
                decoration: fieldDecoration.copyWith(labelText: 'Kategori'),
                icon: Icons.category_outlined,
                value: _selectedCategoryName(categories),
                placeholder: 'Pilih kategori dan subkategori',
                onTap: () => _pickCategory(categories),
              ),
            ],
            const SizedBox(height: 12),
            TransactionPickerField(
              decoration: fieldDecoration.copyWith(labelText: 'Tanggal'),
              icon: Icons.calendar_month_outlined,
              value: DateFormat('d MMM yyyy • HH:mm', 'id_ID').format(_date),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 4,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  _saving ||
                      draftInvalid ||
                      _account == null ||
                      int.tryParse(_amount) == null ||
                      int.parse(_amount) <= 0 ||
                      (_type == 'transfer' &&
                          !_draftTransfer &&
                          (_recipientName.text.trim().isEmpty ||
                              _recipientAccount.text.trim().isEmpty))
                  ? null
                  : _saveTransaction,
              child: Text(_saving ? 'Menyimpan…' : 'Simpan transaksi'),
            ),
            if (_saveError != null)
              Text(
                _saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

class TransactionPickerField extends StatelessWidget {
  const TransactionPickerField({
    super.key,
    required this.decoration,
    required this.icon,
    required this.value,
    required this.onTap,
    this.placeholder = '',
  });

  final InputDecoration decoration;
  final IconData icon;
  final String? value;
  final VoidCallback? onTap;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: decoration.labelText,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: InputDecorator(
            decoration: decoration
                .copyWith(prefixIcon: Icon(icon, color: scheme.primary))
                .applyDefaults(Theme.of(context).inputDecorationTheme),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: value == null ? AppTheme.mutedText : null,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withValues(alpha: .62),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<LedgyCategoryChoice?> showLedgyCategoryPicker(
  BuildContext context, {
  required String type,
  required List<Category> existingCategories,
}) {
  final panel = _CategoryPickerPanel(
    type: type,
    existingCategories: existingCategories,
  );
  if (MediaQuery.sizeOf(context).width >= 700) {
    return showDialog<LedgyCategoryChoice>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
          child: GlassMenuSurface(padding: EdgeInsets.zero, child: panel),
        ),
      ),
    );
  }
  return showModalBottomSheet<LedgyCategoryChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: .88,
      child: GlassMenuSurface(
        padding: EdgeInsets.zero,
        child: SafeArea(top: false, child: panel),
      ),
    ),
  );
}

class _CategoryPickerPanel extends StatefulWidget {
  const _CategoryPickerPanel({
    required this.type,
    required this.existingCategories,
  });

  final String type;
  final List<Category> existingCategories;

  @override
  State<_CategoryPickerPanel> createState() => _CategoryPickerPanelState();
}

class _CategoryPickerPanelState extends State<_CategoryPickerPanel> {
  final _search = TextEditingController();
  final Set<String> _openedGroups = {'Acara Sosial'};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_LedgerCategoryGroup> get _groups {
    final catalog = widget.type == 'income'
        ? incomeCategoryGroups
        : expenseCategoryGroups;
    final groups = {
      for (final entry in catalog.entries) entry.key: entry.value.toSet(),
    };
    for (final category in widget.existingCategories) {
      if (category.kind != widget.type || category.deletedAt != null) continue;
      final name = widget.type == 'income'
          ? incomeCategoryName(category.name)
          : category.name;
      final parts = name.split('•').map((part) => part.trim()).toList();
      final children = groups.putIfAbsent(parts.first, () => <String>{});
      if (parts.length > 1) children.add(parts.skip(1).join(' • '));
    }
    return groups.entries
        .map(
          (entry) => _LedgerCategoryGroup(
            name: entry.key,
            children: entry.value.toList(),
          ),
        )
        .toList();
  }

  void _choose(LedgyCategoryChoice choice) => Navigator.pop(context, choice);

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final groups = _groups.where((group) {
      return query.isEmpty ||
          group.name.toLowerCase().contains(query) ||
          group.children.any((child) => child.toLowerCase().contains(query));
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .28),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Tutup',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.type == 'expense'
                      ? 'Pilih kategori'
                      : 'Pilih kategori pemasukan',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Cari kategori atau subkategori',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'SEMUA KATEGORI',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: .8,
                color: AppTheme.mutedText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Text(
                      'Kategori tidak ditemukan.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .6),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final expandable = group.children.isNotEmpty;
                      final expanded =
                          expandable &&
                          (_openedGroups.contains(group.name) ||
                              query.isNotEmpty);
                      return _CategoryGroupTile(
                        group: group,
                        expanded: expanded,
                        searchableQuery: query,
                        onTapGroup: () {
                          if (!expandable) {
                            _choose(LedgyCategoryChoice.root(group.name));
                            return;
                          }
                          setState(() {
                            if (_openedGroups.contains(group.name)) {
                              _openedGroups.remove(group.name);
                            } else {
                              _openedGroups.add(group.name);
                            }
                          });
                        },
                        onChooseChild: (child) => _choose(
                          LedgyCategoryChoice.child(group.name, child),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGroupTile extends StatelessWidget {
  const _CategoryGroupTile({
    required this.group,
    required this.expanded,
    required this.searchableQuery,
    required this.onTapGroup,
    required this.onChooseChild,
  });

  final _LedgerCategoryGroup group;
  final bool expanded;
  final String searchableQuery;
  final VoidCallback onTapGroup;
  final ValueChanged<String> onChooseChild;

  @override
  Widget build(BuildContext context) {
    final visual = _categoryVisual(group.name);
    final visibleChildren = group.children.where((child) {
      return searchableQuery.isEmpty ||
          child.toLowerCase().contains(searchableQuery) ||
          group.name.toLowerCase().contains(searchableQuery);
    }).toList();
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTapGroup,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: visual.color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(visual.icon, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (group.children.isNotEmpty)
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: visual.color,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Column(
              children: visibleChildren
                  .map(
                    (child) => Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onChooseChild(child),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                visual.icon,
                                size: AppTheme.navigationIconSize,
                                color: visual.color,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(child)),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: AppTheme.mutedText,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class LedgyCategoryChoice {
  const LedgyCategoryChoice._({required this.databaseName});

  factory LedgyCategoryChoice.root(String name) =>
      LedgyCategoryChoice._(databaseName: name);

  factory LedgyCategoryChoice.child(String parent, String child) =>
      LedgyCategoryChoice._(databaseName: '$parent • $child');

  final String databaseName;
}

class _LedgerCategoryGroup {
  const _LedgerCategoryGroup({required this.name, this.children = const []});

  final String name;
  final List<String> children;
}
