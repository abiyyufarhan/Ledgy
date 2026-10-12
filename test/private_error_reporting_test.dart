import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/privacy/error_reporting.dart';

void main() {
  test('uncaught errors never forward private SQL, widget text or stack', () {
    final originalFlutter = FlutterError.onError;
    final originalPlatform = PlatformDispatcher.instance.onError;
    final originalPresenter = FlutterError.presentError;
    final originalBuilder = ErrorWidget.builder;
    addTearDown(() {
      FlutterError.onError = originalFlutter;
      PlatformDispatcher.instance.onError = originalPlatform;
      FlutterError.presentError = originalPresenter;
      ErrorWidget.builder = originalBuilder;
    });
    installPrivateErrorReporting();
    final events = <FlutterErrorDetails>[];
    FlutterError.presentError = events.add;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError('PRIVATE SQL amount 200000'),
        stack: StackTrace.fromString('PRIVATE STACK'),
      ),
    );
    expect(
      PlatformDispatcher.instance.onError!(
        StateError('PRIVATE NOTE'),
        StackTrace.fromString('PRIVATE STACK'),
      ),
      isTrue,
    );
    expect(events.length, 2);
    for (final event in events) {
      expect(event.exceptionAsString(), isNot(contains('PRIVATE')));
      expect(event.stack, isNull);
      expect(event.informationCollector, isNull);
    }
  });
}
