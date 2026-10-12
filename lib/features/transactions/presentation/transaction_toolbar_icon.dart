import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum TransactionToolbarSymbol { filter, download }

/// Drawn as vectors so release bundles with an older subset icon font still
/// show the toolbar controls. The enclosing button provides the semantic label.
class TransactionToolbarIcon extends StatelessWidget {
  const TransactionToolbarIcon({
    super.key,
    required this.symbol,
    this.size = AppTheme.transactionIconSize,
  });

  final TransactionToolbarSymbol symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = iconTheme.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TransactionToolbarPainter(
          symbol: symbol,
          color: color.withValues(alpha: color.a * (iconTheme.opacity ?? 1)),
        ),
      ),
    );
  }
}

class _TransactionToolbarPainter extends CustomPainter {
  const _TransactionToolbarPainter({required this.symbol, required this.color});
  final TransactionToolbarSymbol symbol;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    switch (symbol) {
      case TransactionToolbarSymbol.filter:
        canvas.drawPath(
          Path()
            ..moveTo(2, 3)
            ..lineTo(22, 3)
            ..lineTo(14, 12)
            ..lineTo(14, 21)
            ..lineTo(10, 19)
            ..lineTo(10, 12)
            ..close(),
          paint,
        );
      case TransactionToolbarSymbol.download:
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(
          Path()
            ..moveTo(12, 3)
            ..lineTo(12, 15)
            ..moveTo(7, 10)
            ..lineTo(12, 15)
            ..lineTo(17, 10)
            ..moveTo(3, 16)
            ..lineTo(3, 20)
            ..quadraticBezierTo(3, 21, 4, 21)
            ..lineTo(20, 21)
            ..quadraticBezierTo(21, 21, 21, 20)
            ..lineTo(21, 16),
          paint,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TransactionToolbarPainter oldDelegate) =>
      symbol != oldDelegate.symbol || color != oldDelegate.color;
}
