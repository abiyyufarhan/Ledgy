import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_pipeline.dart';
import 'package:ledgy/features/quick_input/presentation/parser_lab_page.dart';
import 'package:ledgy/features/quick_input/presentation/parser_settings.dart';
import 'package:ledgy/features/quick_input/presentation/quick_input_providers.dart';

import 'support/parser_corpus.dart';
import 'support/fake_parser_failures.dart';

void main() {
  test('inspect menjalankan aturan yang sama dan memperlihatkan confidence/warning', () async {
    const pipeline = ParserPipeline();
    final ctx = corpusContext();
    const text = 'makan tanpa jumlah';
    final result = await pipeline.inspect(text, ctx);
    final normal = (await pipeline.parse(text, ctx)).single;
    expect(result.drafts.single.amount, normal.amount);
    expect(result.drafts.single.confidence, normal.confidence);
    expect(
      result.steps.map((s) => s.name),
      containsAll([
        'Normalisasi',
        'Jumlah',
        'Kategori dan catatan',
        'Confidence',
        'Pipeline',
      ]),
    );
    expect(result.steps.last.detail, contains('nonaktif'));
  });
  Future<void> open(
    WidgetTester tester,
    FakeParserFailures failures, {
    bool settings = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          parserContextProvider.overrideWith((ref) async => corpusContext()),
          parserFailureRepositoryProvider.overrideWithValue(failures),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: settings
              ? const Scaffold(
                  body: SingleChildScrollView(child: ParserSettings()),
                )
              : const ParserLabPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Lab kosong, hasil, langkah aturan, nominal kosong dan warning tanpa simpan',
    (tester) async {
      final failures = FakeParserFailures();
      await open(tester, failures);
      expect(find.textContaining('Hasil akan muncul'), findsOneWidget);
      await tester.tap(find.text('Urai kalimat'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tempel atau ketik'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('parser-lab-input')),
        'makan tanpa jumlah',
      );
      await tester.tap(find.text('Urai kalimat'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Jumlah: kosong'), findsOneWidget);
      expect(find.textContaining('amount_missing:'), findsOneWidget);
      expect(find.textContaining('Normalisasi'), findsOneWidget);
      expect(find.text('Simpan'), findsNothing);
      expect(failures.rows, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('pengaturan mati, opt-in eksplisit dan Lab debug dapat dibuka', (
    tester,
  ) async {
    final failures = FakeParserFailures();
    await open(tester, failures, settings: true);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(failures.active, isTrue);
    await tester.tap(find.text('Lab parser'));
    await tester.pumpAndSettle();
    expect(find.byType(ParserLabPage), findsOneWidget);
  });
  testWidgets('Lab menerima font 200 persen tanpa overflow', (tester) async {
    await open(tester, FakeParserFailures(), scale: 2);
    await tester.enterText(
      find.byKey(const ValueKey('parser-lab-input')),
      'kopi 35rb BCA',
    );
    await tester.tap(find.text('Urai kalimat'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
