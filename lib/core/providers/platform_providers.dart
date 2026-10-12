import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keep the native exit operation injectable; widget tests must never terminate.
final exitApplicationProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await SystemNavigator.pop();
      return;
    }
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  };
});
