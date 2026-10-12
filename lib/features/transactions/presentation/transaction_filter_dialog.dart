import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_dropdown_field.dart';
import '../../../core/widgets/glass_menu.dart';
import '../../categories/domain/category_catalog.dart';
import '../../reports/domain/finance_report.dart';
import '../domain/transaction_filters.dart';

Future<T?> showTransactionGlassDialog<T>(BuildContext context, Widget child) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Tutup dialog',
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .54),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppTheme.menuDuration,
      pageBuilder: (context, _, _) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppTheme.pagePadding),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppTheme.transactionDialogWidth,
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: GlassMenuSurface(
            padding: const EdgeInsets.all(AppTheme.pagePadding),
            child: child,
          ),
        ),
      ),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

class TransactionFilterDialog extends StatefulWidget {
  const TransactionFilterDialog({
    super.key,
    required this.initial,
    required this.accounts,
    required this.categories,
    required this.categoryIcon,
    required this.categoryColor,
  });
  final TransactionFilters initial;
  final List<Account> accounts;
  final List<Category> categories;
  final IconData Function(String) categoryIcon;
  final Color Function(String) categoryColor;

  @override
  State<TransactionFilterDialog> createState() =>
      _TransactionFilterDialogState();
}

class _TransactionFilterDialogState extends State<TransactionFilterDialog> {
  String? _type;
  String? _category;
  String? _account;
  @override
  void initState() {
    super.initState();
    _type = ['income', 'expense'].contains(widget.initial.type)
        ? widget.initial.type
        : null;
    _category = widget.initial.categoryName;
    _account = widget.accounts.any((a) => a.id == widget.initial.accountId)
        ? widget.initial.accountId
        : null;
  }

  Future<void> _chooseCategory() async {
    final result = await showTransactionGlassDialog<_CategorySelection>(
      context,
      _FilterCategoryPicker(
        type: _type,
        categories: widget.categories,
        selected: _category,
        categoryIcon: widget.categoryIcon,
        categoryColor: widget.categoryColor,
      ),
    );
    if (mounted && result != null) setState(() => _category = result.name);
  }

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
                'Filter Transaksi',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Tutup filter',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sectionSpacing),
        GlassDropdownFormField<String?>(
          key: const ValueKey('transaction-filter-type'),
          initialValue: _type,
          icon: null,
          decoration: const InputDecoration(labelText: 'Tipe Transaksi'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Semua')),
            DropdownMenuItem(value: 'income', child: Text('Pemasukan')),
            DropdownMenuItem(value: 'expense', child: Text('Pengeluaran')),
          ],
          onChanged: (value) => setState(() {
            if (_type != value) _category = null;
            _type = value;
          }),
        ),
        const SizedBox(height: AppTheme.fieldSpacing),
        Semantics(
          button: true,
          label: 'Kategori',
          child: InkWell(
            key: const ValueKey('transaction-filter-category'),
            borderRadius: BorderRadius.circular(AppTheme.fieldSpacing),
            onTap: _chooseCategory,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Kategori',
                prefixIcon: _category == null
                    ? null
                    : Icon(
                        widget.categoryIcon(_category!),
                        color: widget.categoryColor(_category!),
                      ),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(_category ?? 'Semua Kategori')),
                  const Icon(Icons.expand_more_rounded),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.fieldSpacing),
        GlassDropdownFormField<String?>(
          key: const ValueKey('transaction-filter-account'),
          initialValue: _account,
          icon: null,
          decoration: const InputDecoration(labelText: 'Akun'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Semua Akun')),
            for (final account in widget.accounts)
              DropdownMenuItem(value: account.id, child: Text(account.name)),
          ],
          onChanged: (value) => setState(() => _account = value),
        ),
        const SizedBox(height: AppTheme.sectionSpacing),
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = [
              OutlinedButton(
                onPressed: () => setState(() {
                  _type = null;
                  _category = null;
                  _account = null;
                }),
                child: const Text('Reset'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  TransactionFilters(
                    type: _type,
                    categoryName: _category,
                    accountId: _account,
                  ),
                ),
                child: const Text('Terapkan'),
              ),
            ];
            if (constraints.maxWidth <
                MediaQuery.textScalerOf(context)
                    .scale(AppTheme.minTouchTarget * 5)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buttons.first,
                  const SizedBox(height: AppTheme.compactSpacing),
                  buttons.last,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: buttons.first),
                const SizedBox(width: AppTheme.fieldSpacing),
                Expanded(child: buttons.last),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _CategorySelection {
  const _CategorySelection(this.name);
  final String? name;
}

class _FilterCategoryPicker extends StatefulWidget {
  const _FilterCategoryPicker({
    required this.type,
    required this.categories,
    required this.selected,
    required this.categoryIcon,
    required this.categoryColor,
  });
  final String? type;
  final List<Category> categories;
  final String? selected;
  final IconData Function(String) categoryIcon;
  final Color Function(String) categoryColor;
  @override
  State<_FilterCategoryPicker> createState() => _FilterCategoryPickerState();
}

class _FilterCategoryPickerState extends State<_FilterCategoryPicker> {
  late final Map<String, Set<String>> _groups;
  late final Set<String> _opened;
  @override
  void initState() {
    super.initState();
    _groups = {
      if (widget.type != 'income')
        for (final entry in expenseCategoryGroups.entries)
          entry.key: entry.value.toSet(),
    };
    if (widget.type != 'expense') {
      for (final entry in incomeCategoryGroups.entries) {
        _groups.putIfAbsent(entry.key, () => <String>{}).addAll(entry.value);
      }
    }
    for (final category in widget.categories) {
      if (category.deletedAt != null ||
          (widget.type != null && category.kind != widget.type)) {
        continue;
      }
      final parts = canonicalCategory(
        category.kind == 'income'
            ? incomeCategoryName(category.name)
            : category.name,
      ).split(' • ');
      final children = _groups.putIfAbsent(parts.first, () => <String>{});
      if (parts.length > 1) children.add(parts.skip(1).join(' • '));
    }
    _opened = {
      'Acara Sosial',
      if (widget.selected != null) categoryParent(widget.selected!),
    };
  }

  void _choose(String? name) =>
      Navigator.pop(context, _CategorySelection(name));

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Semua kategori',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Tutup kategori',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      const SizedBox(height: AppTheme.compactSpacing),
      Expanded(
        child: ListView.builder(
          itemCount: _groups.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return ListTile(
                title: const Text('Semua Kategori'),
                onTap: () => _choose(null),
              );
            }
            final group = _groups.entries.elementAt(index - 1);
            final opened = _opened.contains(group.key);
            final color = widget.categoryColor(group.key);
            final icon = widget.categoryIcon(group.key);
            return Column(
              children: [
                ListTile(
                  minVerticalPadding: AppTheme.menuRowPadding,
                  leading: CircleAvatar(
                    backgroundColor: color,
                    child: Icon(
                      icon,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  title: Text(group.key),
                  trailing: group.value.isEmpty
                      ? null
                      : Icon(opened ? Icons.expand_less : Icons.expand_more),
                  onTap: () {
                    if (group.value.isEmpty) {
                      _choose(group.key);
                      return;
                    }
                    setState(() {
                      if (opened) {
                        _opened.remove(group.key);
                      } else {
                        _opened.add(group.key);
                      }
                    });
                  },
                ),
                if (opened && group.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppTheme.menuRowPadding,
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(icon, color: color),
                          title: Text('Semua dalam ${group.key}'),
                          onTap: () => _choose(group.key),
                        ),
                        for (final child in group.value)
                          ListTile(
                            leading: Icon(icon, color: color),
                            title: Text(child),
                            selected:
                                widget.selected == '${group.key} • $child',
                            onTap: () => _choose('${group.key} • $child'),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
