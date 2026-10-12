import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:ledgy/app/mvp_screens.dart';
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/transactions/data/repositories/transactions_repository_impl.dart';

class _RecordingTransactions extends TransactionsRepository {
  _RecordingTransactions(this.database) : super(database.transactionsDao);
  final AppDatabase database;
  TransactionsCompanion? saved;

  @override
  Future<void> save(TransactionsCompanion value) async => saved = value;
}

final _previewKey = GlobalKey();

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is InputDecorator && widget.decoration.labelText == label,
);

Future<_RecordingTransactions> _openEditor(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final repository = _RecordingTransactions(db);
  final now = DateTime.now();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        transactionsRepositoryProvider.overrideWithValue(repository),
        accountsProvider.overrideWith(
          (ref) => Stream.value([
            for (final name in ['Bank Jago', 'Tunai'])
              Account(
                id: name,
                name: name,
                initialBalance: 0,
                createdAt: now,
                updatedAt: now,
                isDirty: false,
              ),
          ]),
        ),
        categoriesProvider.overrideWith(
          (ref) => Stream.value([
            Category(
              id: 'refund',
              name: 'Lainnya • Refund',
              kind: 'income',
              createdAt: now,
              updatedAt: now,
              isDirty: false,
            ),
            Category(
              id: 'salary',
              name: 'Gaji',
              kind: 'income',
              createdAt: now,
              updatedAt: now,
              isDirty: false,
            ),
          ]),
        ),
      ],
      child: RepaintBoundary(
        key: _previewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTransactionEditor(context),
                child: const Text('Buka editor'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka editor'));
  await tester.pumpAndSettle();
  return repository;
}

Future<void> preview(WidgetTester tester, String name) async {
  if (Platform.environment['LEDGY_VISUAL_QA'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    await Directory('build/ui-previews').create(recursive: true);
    await File('build/ui-previews/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
      await (FontLoader('Manrope')..addFont(
            File('assets/fonts/NotoSans-Regular.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('ukuran kolom transaksi seragam ${size.width}px', (
      tester,
    ) async {
      await _openEditor(tester, size);
      expect(find.text('Transaksi Baru'), findsOneWidget);
      final amountSize = tester.getSize(field('Jumlah'));
      for (final label in ['Dari akun', 'Kategori', 'Tanggal']) {
        expect(tester.getSize(field(label)), amountSize);
      }
      final noteSize = tester.getSize(field('Catatan (opsional)'));
      expect(noteSize.width, amountSize.width);
      expect(noteSize.height, greaterThan(amountSize.height));
      await preview(tester, 'new-transaction-${size.width.toInt()}');

      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();
      final recipientSize = tester.getSize(field('Nama Penerima'));
      expect(recipientSize.height, amountSize.height);
      expect(tester.getSize(field('Rekening Penerima')), recipientSize);
      expect(find.text('Ke akun'), findsNothing);
      expect(find.text('Kategori'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tanggal, jam, menit dan catatan tersimpan', (tester) async {
    final repository = await _openEditor(tester, const Size(1280, 900));
    await tester.enterText(find.byType(TextField).first, '25000');
    await tester.tap(field('Tanggal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final selectedDate = DateTime(2026, 10, 7, 21, 45);
    final dateContext = tester.element(find.byType(DatePickerDialog));
    final localizations = MaterialLocalizations.of(dateContext);
    await tester.enterText(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(TextFormField),
      ),
      localizations.formatCompactDate(selectedDate),
    );
    await tester.tap(find.text(localizations.okButtonLabel));
    await tester.pumpAndSettle();
    final timeInputs = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(timeInputs.at(0), '21');
    await tester.enterText(timeInputs.at(1), '45');
    await tester.tap(find.text(localizations.okButtonLabel));
    await tester.pumpAndSettle();
    expect(
      find.text(DateFormat('d MMM yyyy • HH:mm', 'id_ID').format(selectedDate)),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField).last,
      'Baris satu\nBaris dua',
    );
    await tester.tap(find.text('Simpan transaksi'));
    await tester.pumpAndSettle();
    expect(repository.saved!.occurredAt.value, selectedDate.toUtc());
    expect(repository.saved!.note.value, 'Baris satu\nBaris dua');
    expect(repository.saved!.amount.value, 25000);
    expect(find.text('Transaksi Baru'), findsNothing);
  });

  testWidgets('pemasukan memakai Menuju Akun dan katalog lengkap', (
    tester,
  ) async {
    final repository = await _openEditor(tester, const Size(1280, 900));
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();
    expect(find.text('Menuju Akun'), findsOneWidget);
    expect(find.text('Dari akun'), findsNothing);
    await tester.tap(field('Kategori'));
    await tester.pumpAndSettle();
    for (final name in [
      'Acara Sosial',
      'Pemasukan',
      'Pencairan Pinjaman',
      'Tabungan',
      'Lainnya',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Amal & Donasi'), findsOneWidget);
    expect(find.text('Hadiah'), findsOneWidget);
    await preview(tester, 'income-category-picker');
    await tester.enterText(find.byType(TextField).last, 'Refund');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund').last);
    await tester.pumpAndSettle();
    expect(find.text('Lainnya • Refund'), findsOneWidget);
    await preview(tester, 'new-income-transaction');
    await tester.enterText(find.byType(TextField).first, '50000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan transaksi'));
    await tester.pumpAndSettle();
    expect(repository.saved!.categoryId.value, 'refund');
    expect(repository.saved!.type.value, 'income');
  });

  testWidgets('transfer menyimpan penerima tanpa kehilangan nol awal', (
    tester,
  ) async {
    final repository = await _openEditor(tester, const Size(1280, 900));
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '125000');
    await tester.enterText(find.byType(TextField).at(1), ' Budi Santoso ');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).at(2), '001234567890');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await preview(tester, 'new-transfer-transaction');
    await tester.tap(find.text('Simpan transaksi'));
    await tester.pumpAndSettle();
    expect(repository.saved!.recipientName.value, 'Budi Santoso');
    expect(repository.saved!.recipientAccount.value, '001234567890');
    expect(repository.saved!.toAccountId.value, isNull);
    expect(repository.saved!.categoryId.value, isNull);
    expect(repository.saved!.type.value, 'transfer');
  });

  testWidgets('membatalkan waktu mempertahankan tanggal semula', (
    tester,
  ) async {
    await _openEditor(tester, const Size(1280, 900));
    final original = tester
        .widget<Text>(
          find
              .descendant(of: field('Tanggal'), matching: find.byType(Text))
              .first,
        )
        .data;
    await tester.tap(field('Tanggal'));
    await tester.pumpAndSettle();
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    );
    await tester.tap(find.text(localizations.okButtonLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(localizations.cancelButtonLabel));
    await tester.pumpAndSettle();
    expect(find.text(original!), findsOneWidget);
  });

  testWidgets('form tetap dapat digulir dengan font besar', (tester) async {
    await _openEditor(tester, const Size(390, 844), textScale: 1.5);
    await tester.ensureVisible(find.text('Simpan transaksi'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
