import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Default Flutter diagnostics can include widget text or SQL parameters.
/// Never forward the original exception, stack, or diagnostic collectors.
void installPrivateErrorReporting() {
  void reportSafely() => FlutterError.presentError(
    FlutterErrorDetails(
      exception: FlutterError(
        'Ledgy mengalami kendala. Buka ulang aplikasi untuk mencoba lagi.',
      ),
      library: 'Ledgy',
    ),
  );
  FlutterError.onError = (_) => reportSafely();
  PlatformDispatcher.instance.onError = (_, _) {
    reportSafely();
    return true;
  };
  ErrorWidget.builder = (_) => const ColoredBox(
    color: AppTheme.privacySurface,
    child: Center(
      child: Text(
        'Tampilan belum dapat dimuat. Buka ulang Ledgy.',
        textDirection: TextDirection.ltr,
      ),
    ),
  );
}
