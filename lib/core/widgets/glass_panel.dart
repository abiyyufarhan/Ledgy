import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Blur is reserved for the single main panel, not individual form/list rows.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.panelRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppTheme.glassBlur,
          sigmaY: AppTheme.glassBlur,
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.sectionSpacing),
            child: child,
          ),
        ),
      ),
    ),
  );
}
