import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_context.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';
import 'package:ledgy/features/quick_input/domain/receipt/ocr_line.dart';
import 'package:ledgy/features/quick_input/domain/receipt/receipt_scan_backend.dart';
import 'package:ledgy/features/quick_input/presentation/draft_confirmation_sheet.dart';
import 'package:ledgy/features/quick_input/presentation/quick_input_providers.dart';
import 'package:ledgy/features/quick_input/presentation/receipt_providers.dart';
import 'package:ledgy/features/quick_input/presentation/receipt_scan_page.dart';

class FakeScan implements ReceiptScanBackend {
  final photo = ReceiptPhoto(
    '/app/private/temp/receipt.jpg',
    Uint8List.fromList(img.encodePng(img.Image(width: 10, height: 20))),
  );
  int removed = 0, recognized = 0, picked = 0;
  bool empty = false, cancel = false;
  Completer<List<OcrLine>>? gate;
  @override
  Future<ReceiptPhoto?> pick(ReceiptImageSource source) async {
    picked++;
    return cancel ? null : photo;
  }

  @override
  Future<ReceiptPhoto?> recover() async => null;
  @override
  Future<void> remove(ReceiptPhoto photo) async {
    removed++;
  }

  @override
  Future<List<OcrLine>> recognize(ReceiptPhoto photo) async {
    recognized++;
    if (gate != null) return gate!.future;
    return empty
        ? []
        : [
            for (final entry in [
              'CAFE',
              '08/10/2026',
              'KOPI 35.000',
              'TOTAL 35.000',
              'TUNAI',
            ].asMap().entries)
              OcrLine(
                text: entry.value,
                left: 0,
                top: entry.key * 30,
                right: 600,
                bottom: entry.key * 30 + 20,
              ),
          ];
  }
}

Future<void> open(
  WidgetTester tester,
  FakeScan backend, {
  TargetPlatform platform = TargetPlatform.android,
  bool debug = false,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final date = DateTime.utc(2026, 10, 8);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        receiptScanBackendProvider.overrideWithValue(backend),
        receiptSavePhotoProvider.overrideWith((ref) async => false),
        parserContextProvider.overrideWith(
          (ref) async => ParserContext(
            clock: FixedClock(date),
            accounts: [ParserAccount(id: 'cash', name: 'Tunai')],
            categories: [
              const ParserCategory(
                id: 'food',
                name: 'Makanan',
                type: TransactionType.expense,
              ),
            ],
          ),
        ),
        accountsProvider.overrideWith(
          (ref) => Stream.value([
            Account(
              id: 'cash',
              name: 'Tunai',
              initialBalance: 0,
              createdAt: date,
              updatedAt: date,
              isDirty: false,
            ),
          ]),
        ),
        categoriesProvider.overrideWith(
          (ref) => Stream.value([
            Category(
              id: 'food',
              name: 'Makanan',
              kind: 'expense',
              createdAt: date,
              updatedAt: date,
              isDirty: false,
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReceiptScanPage(debugOnly: debug),
                ),
              ),
              child: const Text('Pindai'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Pindai'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  testWidgets(
    'gallery preview -> OCR -> confirmation -> discard deletes temp photo',
    (tester) async {
      final backend = FakeScan();
      await open(tester, backend);
      await tap(tester, 'receipt-gallery');
      expect(find.byKey(const ValueKey('receipt-preview')), findsOneWidget);
      await tap(tester, 'receipt-scan');
      expect(backend.recognized, 1);
      expect(find.byType(DraftConfirmationSheet), findsOneWidget);
      expect(find.text('Lihat teks OCR'), findsNothing);
      await tap(tester, 'draft-input-details');
      expect(find.text('Lihat teks OCR'), findsOneWidget);
      await tester.ensureVisible(find.text('Buang'));
      await tester.tap(find.text('Buang'));
      await tester.pumpAndSettle();
      expect(backend.removed, 1);
      expect(find.byKey(const ValueKey('receipt-preview')), findsNothing);
    },
  );
  testWidgets('cancel picker does not run OCR; leaving preview deletes photo', (
    tester,
  ) async {
    final backend = FakeScan()..cancel = true;
    await open(tester, backend);
    await tap(tester, 'receipt-camera');
    expect(backend.recognized, 0);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('receipt-scan')))
          .onPressed,
      isNull,
    );
    backend.cancel = false;
    await tap(tester, 'receipt-gallery');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(backend.removed, 1);
  });
  testWidgets(
    'empty OCR gives helpful inline retry and cleans photo on leaving',
    (tester) async {
      final backend = FakeScan()..empty = true;
      await open(tester, backend);
      await tap(tester, 'receipt-camera');
      await tap(tester, 'receipt-scan');
      expect(find.textContaining('Teks belum terbaca'), findsOneWidget);
      expect(find.byType(DraftConfirmationSheet), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(backend.removed, 1);
    },
  );
  testWidgets('non Android never offers camera, gallery or OCR', (
    tester,
  ) async {
    final backend = FakeScan();
    await open(tester, backend, platform: TargetPlatform.windows);
    expect(find.text('Pemindaian struk tersedia di Android'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-camera')), findsNothing);
    expect(backend.picked, 0);
  });
  testWidgets('debug OCR produces export button without saving drafts', (
    tester,
  ) async {
    final backend = FakeScan();
    await open(tester, backend, debug: true);
    await tap(tester, 'receipt-gallery');
    await tap(tester, 'receipt-scan');
    expect(find.text('Ekspor OcrLine ke JSON'), findsOneWidget);
    expect(find.byType(DraftConfirmationSheet), findsNothing);
  });
  testWidgets('guide and actions fit at 200% font scale', (tester) async {
    await open(tester, FakeScan(), scale: 2);
    expect(tester.takeException(), isNull);
    await tap(tester, 'receipt-camera');
    expect(tester.takeException(), isNull);
  });
}
