import 'package:flutter/material.dart';

/// Vector source shared by the startup UI and generated launcher assets.
abstract final class LedgyBrand {
  static const background = Color(0xFF071426);
  static const blue = Color(0xFF3564C9);
  static const cyan = Color(0xFF32C2E8);
  static const ink = Color(0xFFF3F7FF);
}

class LedgyMark extends StatelessWidget {
  const LedgyMark({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Logo Ledgy',
    image: true,
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: const LedgyMarkPainter(),
      ),
    ),
  );
}

class LedgyMarkPainter extends CustomPainter {
  const LedgyMarkPainter({this.tile = true});
  final bool tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 108, 108),
          const Radius.circular(24),
        ),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [LedgyBrand.blue, LedgyBrand.background],
          ).createShader(const Rect.fromLTWH(0, 0, 108, 108)),
      );
    }
    final outline = Paint()
      ..color = LedgyBrand.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 34, 52, 42),
        const Radius.circular(7),
      ),
      outline,
    );
    canvas.drawLine(const Offset(36, 44), const Offset(70, 44), outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 50, 24, 17),
        const Radius.circular(4),
      ),
      Paint()..color = LedgyBrand.cyan,
    );
    canvas.drawCircle(
      const Offset(68, 58.5),
      2.5,
      Paint()..color = LedgyBrand.background,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LedgyMarkPainter oldDelegate) => oldDelegate.tile != tile;
}
