import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/expanding_glass_button.dart';
import '../../../core/widgets/glass_menu.dart';
import 'advanced_pages.dart';

class BudgetHubPage extends StatelessWidget {
  const BudgetHubPage({super.key, this.initialSection = 0, this.initialMonth});
  final int initialSection;
  final DateTime? initialMonth;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: initialSection,
      children: [
        BudgetPlansPage(
          embedded: true,
          initialMonth: initialMonth,
          appBarTitle: _BudgetTitle(section: initialSection),
        ),
        RecurringPage(
          embedded: true,
          appBarTitle: _BudgetTitle(section: initialSection),
        ),
      ],
    ),
    floatingActionButton: ExpandingGlassButton(
      key: const ValueKey('csv-print-button'),
      label: 'Print',
      tooltip: 'Print — Ekspor / impor CSV',
      size: AppTheme.printButtonSize,
      expandedWidth: AppTheme.printExpandedWidth,
      trailing: const Icon(Icons.print_outlined),
      onPressed: () => context.push('/csv'),
    ),
  );
}

class _BudgetTitle extends StatelessWidget {
  const _BudgetTitle({required this.section});
  final int section;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= AppTheme.sidebarBreakpoint) {
      return const Text('Anggaran');
    }
    return Builder(
      builder: (anchor) => InkWell(
        key: const ValueKey('budget-section-menu'),
        borderRadius: BorderRadius.circular(AppTheme.sidebarItemRadius),
        onTap: () async {
          final selected = await showGlassMenu<int>(
            context: context,
            anchorContext: anchor,
            selectedValue: section,
            entries: const [
              GlassMenuEntry(
                value: 0,
                label: Text('Anggaran Bulanan'),
                icon: Icon(
                  Icons.calendar_month_outlined,
                  size: AppTheme.sidebarSubitemIconSize,
                ),
              ),
              GlassMenuEntry(
                value: 1,
                label: Text('Transaksi Berulang'),
                icon: Icon(
                  Icons.autorenew,
                  size: AppTheme.sidebarSubitemIconSize,
                ),
              ),
            ],
          );
          if (selected != null && context.mounted) {
            context.go(
              selected.value == 1 ? '/budget?section=recurring' : '/budget',
            );
          }
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Anggaran',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
