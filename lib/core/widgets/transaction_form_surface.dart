import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The same opaque dark surface for manual transactions and parsed drafts.
class TransactionFormSurface extends StatelessWidget {
  const TransactionFormSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(AppTheme.panelRadius),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      child: child,
    ),
  );
}
