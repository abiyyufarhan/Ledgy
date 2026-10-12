import 'package:flutter/material.dart';

import '../../../app/mvp_screens.dart'
    show ledgyCategoryColor, ledgyCategoryIcon;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/local_finance_repository.dart';

class BudgetProgressCard extends StatelessWidget {
  const BudgetProgressCard({
    super.key,
    required this.progress,
    required this.onTap,
  });
  final BudgetProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = progress;
    final theme = Theme.of(context);
    final color = ledgyCategoryColor(row.category);
    return Semantics(
      button: true,
      label: 'Kelola anggaran ${row.category}',
      child: Tooltip(
        message: 'Ubah atau hapus anggaran',
        child: GlassCard(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.category,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppTheme.compactSpacing),
                        Text(
                          '${formatRupiah(row.spent)} / ${formatRupiah(row.budget.amount)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.menuRowPadding),
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: color,
                    child: Icon(
                      ledgyCategoryIcon(row.category),
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.menuRowPadding),
              LinearProgressIndicator(
                minHeight: 4,
                value: (row.spent / row.budget.amount).clamp(0, 1),
                color: row.spent >= row.budget.amount
                    ? const Color(0xFFFF6380)
                    : row.spent * 100 >= row.budget.amount * 80
                    ? Colors.amber
                    : const Color(0xFF34D399),
              ),
              const SizedBox(height: AppTheme.compactSpacing),
              Text(
                '${(row.spent * 100 / row.budget.amount).toStringAsFixed(0)}% terpakai · Sisa ${formatRupiah(row.budget.amount - row.spent)}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
