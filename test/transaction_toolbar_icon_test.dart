import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/transactions/presentation/transaction_toolbar_icon.dart';

void main() {
  for (final symbol in TransactionToolbarSymbol.values) {
    testWidgets('$symbol menggambar piksel tanpa font MaterialIcons', (
      tester,
    ) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: IconTheme(
              data: const IconThemeData(color: AppTheme.mutedText, opacity: 1),
              child: RepaintBoundary(
                key: boundaryKey,
                child: TransactionToolbarIcon(symbol: symbol),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Icon), findsNothing);
      expect(
        tester.getSize(find.byType(TransactionToolbarIcon)),
        const Size.square(AppTheme.transactionIconSize),
      );
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final raster = await boundary.toImage(pixelRatio: 2);
        try {
          expect(raster.width, AppTheme.transactionIconSize * 2);
          final pixels = (await raster.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var painted = 0;
          for (var offset = 3; offset < pixels.lengthInBytes; offset += 4) {
            if (pixels.getUint8(offset) > 0) painted++;
          }
          expect(painted, greaterThan(100));
          expect(painted, lessThan(raster.width * raster.height));
        } finally {
          raster.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    });
  }
}
