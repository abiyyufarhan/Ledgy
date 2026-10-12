import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Settings use flat rows without per-row blur, with room for large text.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.titleKey,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Key? titleKey;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppTheme.settingsRowGap),
    child: Material(
      color: AppTheme.settingsRowFill,
      borderRadius: BorderRadius.circular(AppTheme.settingsRowRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.settingsRowRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.pagePadding,
            vertical: AppTheme.settingsRowVerticalPadding,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stack =
                  constraints.maxWidth < AppTheme.settingsStackBreakpoint ||
                  MediaQuery.textScalerOf(context).scale(14) > 21;
              final text = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: titleKey,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppTheme.settingsDescriptionGap),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.mutedText),
                  ),
                  if (stack && trailing != null) ...[
                    const SizedBox(height: AppTheme.compactSpacing),
                    Align(alignment: Alignment.centerRight, child: trailing!),
                  ],
                ],
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: AppTheme.settingsRowIconSize),
                  const SizedBox(width: AppTheme.pagePadding),
                  Expanded(child: text),
                  if (!stack && trailing != null) ...[
                    const SizedBox(width: AppTheme.pagePadding),
                    trailing!,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
