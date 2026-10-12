import 'package:flutter/material.dart';

/// A shared midnight backdrop that lets the translucent Ledgy surfaces glow.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF06172D), Color(0xFF030914), Color(0xFF081B34)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-.82, -.96),
                    radius: .78,
                    colors: [Color(0x665B8CFF), Color(0x005B8CFF)],
                  ),
                ),
              ),
            ),
          ),
          const RepaintBoundary(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(1.0, .84),
                    radius: .74,
                    colors: [Color(0x3329D3C1), Color(0x0029D3C1)],
                  ),
                ),
              ),
            ),
          ),
          RepaintBoundary(child: child),
        ],
      ),
    );
  }
}
