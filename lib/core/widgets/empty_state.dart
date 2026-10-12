import 'dart:ui';

import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.enableBackdropBlur = false,
    this.blurSigma = 18,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// True glass blur is costly when a card moves or the window is resized.
  /// Ledgy uses the visually equivalent translucent surface by default.
  /// Enable only for a small, stationary hero card when it is worth the cost.
  final bool enableBackdropBlur;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final surface = Material(
      color: Colors.white.withValues(alpha: .075),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: .17)),
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: .12),
              Colors.white.withValues(alpha: .025),
            ],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000817).withValues(alpha: .28),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: enableBackdropBlur
              ? BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: surface,
                )
              : surface,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 42),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
}

class RingProgress extends StatelessWidget {
  const RingProgress({super.key, required this.value, required this.label});
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(value: value.clamp(0, 1), strokeWidth: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}
