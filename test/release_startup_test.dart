import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/app/ledgy_startup.dart';
import 'package:ledgy/core/branding/ledgy_mark.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/auth/data/cloud_connection.dart';

void main() {
  testWidgets('Startup shows private Ledgy splash during initialization', (
    tester,
  ) async {
    final pending = Completer<CloudConnection>();
    await tester.pumpWidget(LedgyStartup(initialize: () => pending.future));
    expect(find.byType(LedgyMark), findsOneWidget);
    expect(find.text('Ledgy'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Total saldo'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    pending.complete(const CloudConnection());
  });

  testWidgets('Startup error is private and offers retry', (tester) async {
    var attempts = 0;
    final pending = Completer<CloudConnection>();
    await tester.pumpWidget(
      LedgyStartup(
        initialize: () {
          attempts++;
          return attempts == 1
              ? Future.error(StateError('private secret'))
              : pending.future;
        },
      ),
    );
    await tester.pump();
    expect(find.textContaining('private secret'), findsNothing);
    await tester.tap(find.text('Coba lagi'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete(const CloudConnection());
  });

  testWidgets('Splash works at 200% font in a small window', (tester) async {
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const LedgySplash(failed: true),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('Release signing does not fall back to debug keys', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('verifyReleaseSigning'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('**/key.properties'));
    expect(ignore, contains('**/*.jks'));
  });
}
