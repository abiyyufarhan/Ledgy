import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/app/mvp_screens.dart' show TransactionEditor;
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/money_text.dart';
import 'package:ledgy/core/widgets/transaction_form_surface.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';
import 'package:ledgy/features/quick_input/presentation/draft_confirmation_sheet.dart';
import 'package:ledgy/features/transactions/data/repositories/transactions_repository_impl.dart';

class _RecordingRepository extends TransactionsRepository {
  _RecordingRepository(this.database) : super(database.transactionsDao);
  final AppDatabase database;
  int saves = 0;
  bool failNext = false;
  Completer<void>? gate;
  Future<void>? lastSave;

  @override
  Future<void> save(TransactionsCompanion value) => lastSave = _persist(value);

  Future<void> _persist(TransactionsCompanion value) async {
    saves++;
    if (failNext) {
      failNext = false;
      throw StateError('test failure');
    }
    await gate?.future;
    await super.save(value);
  }
}

final _date = DateTime.utc(2020, 10, 8, 10, 45);
final _previewKey = GlobalKey();
TransactionDraft _draft({
  TransactionType type = TransactionType.expense,
  int? amount = 25000,
}) => TransactionDraft(
  type: type,
  amount: amount,
  accountId: 'cash',
  toAccountId: type == TransactionType.transfer ? 'bank' : null,
  categoryId: type == TransactionType.income ? 'salary' : 'food',
  note: 'Catatan draf',
  occurredAt: _date,
  rawText: 'Makan siang 25000 dari Tunai',
  confidence: .85,
);

Finder get _save => find.byKey(const ValueKey('draft-save'));
Finder get _amount => find.descendant(
  of: find.byType(MoneyText),
  matching: find.byType(TextField),
);

Future<_RecordingRepository> _open(
  WidgetTester tester,
  TransactionDraft draft, {
  Size size = const Size(1280, 900),
  double textScale = 1,
  Stream<List<Account>>? accountsStream,
  List<Category> extraCategories = const [],
  TargetPlatform? platform,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final repository = _RecordingRepository(db);
  // Native asset loading requires real asynchronous work outside the fake clock.
  await tester.runAsync(() => db.customSelect('SELECT 1').get());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        transactionsRepositoryProvider.overrideWithValue(repository),
        accountsProvider.overrideWith(
          (ref) =>
              accountsStream ??
              Stream.value([
                for (final entry in {
                  'cash': 'Tunai',
                  'bank': 'Bank Jago',
                }.entries)
                  Account(
                    id: entry.key,
                    name: entry.value,
                    initialBalance: 0,
                    createdAt: _date,
                    updatedAt: _date,
                    isDirty: false,
                  ),
              ]),
        ),
        categoriesProvider.overrideWith(
          (ref) => Stream.value([
            ...extraCategories,
            Category(
              id: 'food',
              name: 'Makan & Minum',
              kind: 'expense',
              createdAt: _date,
              updatedAt: _date,
              isDirty: false,
            ),
            Category(
              id: 'salary',
              name: 'Gaji',
              kind: 'income',
              createdAt: _date,
              updatedAt: _date,
              isDirty: false,
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(
          platform:
              platform ??
              (size.width < AppTheme.sidebarBreakpoint
                  ? TargetPlatform.android
                  : TargetPlatform.windows),
        ),
        builder: (context, child) => RepaintBoundary(
          key: _previewKey,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showDraftConfirmationSheet(context, draft: draft),
              child: const Text('Buka draf'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka draf'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
  return repository;
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  _RecordingRepository? repository,
}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  if (repository != null) {
    await tester.runAsync(() async {
      await tester.tap(finder);
      try {
        await repository.lastSave;
      } catch (_) {
        /* The sheet handles failure. */
      }
      await repository.database.customSelect('SELECT 1').get();
    });
  } else {
    await tester.tap(finder);
  }
  await tester.pumpAndSettle();
}

Future<List<Transaction>> _rows(
  WidgetTester tester,
  _RecordingRepository repository,
) async => (await tester.runAsync(
  () => repository.database.transactionsDao.watchActive().first,
))!;

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
      'UI prompt mengikuti formulir manual dan penerima tersimpan ${size.width}',
      (tester) async {
        final repository = await _open(
          tester,
          _draft(type: TransactionType.transfer).copyWith(
            toAccountId: null,
            recipientName: 'Orang tua',
            recipientAccount: '001234567890',
            rawText: 'Transfer uang ke orang tua sebesar 3000000',
            amount: 3000000,
          ),
          size: size,
        );
        expect(find.text('Transaksi Baru'), findsOneWidget);
        expect(find.text('Konfirmasi transaksi'), findsNothing);
        expect(find.text('Teks asli'), findsNothing);
        expect(find.text('Ke akun'), findsNothing);
        expect(find.text('Simpan transaksi'), findsOneWidget);
        expect(find.byType(TransactionFormSurface), findsOneWidget);
        Finder field(String label) => find.byWidgetPredicate(
          (w) => w is InputDecorator && w.decoration.labelText == label,
        );
        final amountSize = tester.getSize(field('Jumlah'));
        for (final label in ['Dari akun', 'Tanggal']) {
          expect(tester.getSize(field(label)), amountSize);
        }
        final recipientSize = tester.getSize(field('Nama Penerima'));
        expect(recipientSize.height, amountSize.height);
        expect(tester.getSize(field('Rekening Penerima')), recipientSize);
        expect(
          tester.getSize(field('Catatan (opsional)')).height,
          greaterThan(amountSize.height),
        );
        expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
        if (Platform.environment['LEDGY_VISUAL_QA'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_previewKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await Directory('build/ui-previews').create(recursive: true);
            await File(
              'build/ui-previews/prompt-transfer-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await _tap(tester, _save, repository: repository);
        final row = (await _rows(tester, repository)).single;
        expect(row.recipientName, 'Orang tua');
        expect(row.recipientAccount, '001234567890');
        expect(row.amount, 3000000);
        expect(row.toAccountId, isNull);
        expect(row.categoryId, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'penerima wajib dilengkapi dan Edit manual membawa data penerima',
    (tester) async {
      final repository = await _open(
        tester,
        _draft(type: TransactionType.transfer).copyWith(toAccountId: null),
      );
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      expect(find.text('Isi nama penerima.'), findsOneWidget);
      expect(find.text('Isi rekening penerima.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('draft-recipient-name')),
        ' Budi ',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('draft-recipient-account')),
        '00123',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
      await _tap(tester, find.text('Edit manual'));
      expect(find.text('Nama Penerima'), findsOneWidget);
      expect(find.text('Ke akun'), findsNothing);
      await _tap(tester, find.text('Simpan transaksi'), repository: repository);
      final row = (await _rows(tester, repository)).single;
      expect(row.recipientName, 'Budi');
      expect(row.recipientAccount, '00123');
      expect(row.toAccountId, isNull);
    },
  );

  testWidgets(
    'beralih dari penerima ke akun sendiri tidak menyimpan data penerima',
    (tester) async {
      final repository = await _open(
        tester,
        _draft(type: TransactionType.transfer).copyWith(
          toAccountId: null,
          recipientName: 'Budi',
          recipientAccount: '00123',
        ),
      );
      await _tap(tester, find.text('Detail input'));
      await _tap(tester, find.byKey(const ValueKey('draft-transfer-mode')));
      await _tap(tester, find.text('Detail input'));
      expect(find.text('Nama Penerima'), findsNothing);
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      await _tap(
        tester,
        find.byWidgetPredicate(
          (w) => w is InputDecorator && w.decoration.labelText == 'Ke akun',
        ),
      );
      await _tap(tester, find.text('Bank Jago').last);
      await _tap(tester, _save, repository: repository);
      final row = (await _rows(tester, repository)).single;
      expect(row.toAccountId, 'bank');
      expect(row.recipientName, isNull);
      expect(row.recipientAccount, isNull);
    },
  );

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
      'kategori prompt memakai katalog manual dan pencarian ${size.width}',
      (tester) async {
        final repository = await _open(
          tester,
          _draft().copyWith(categoryId: null),
          size: size,
        );
        expect(tester.widget<FilledButton>(_save).onPressed, isNull);
        await _tap(tester, find.byKey(const ValueKey('draft-category')));
        expect(find.text('Pilih kategori'), findsOneWidget);
        expect(find.text('SEMUA KATEGORI'), findsOneWidget);
        expect(find.text('Acara Sosial'), findsOneWidget);
        expect(find.text('Belanja'), findsOneWidget);
        expect(find.byIcon(Icons.shopping_basket_rounded), findsWidgets);
        final search = find.widgetWithText(
          TextField,
          'Cari kategori atau subkategori',
        );
        await tester.enterText(search, 'pesanan makanan');
        await tester.pumpAndSettle();
        expect(find.text('Makan & Minum'), findsWidgets);
        expect(find.text('Pesanan Makanan'), findsOneWidget);
        expect(find.text('Belanja'), findsNothing);
        await _tap(tester, find.text('Pesanan Makanan'));
        expect(find.text('Makan & Minum • Pesanan Makanan'), findsOneWidget);
        expect(find.text('Pilih kategori transaksi.'), findsNothing);
        expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
        final before = (await tester.runAsync(
          () => repository.database.categoriesDao.watchActive().first,
        ))!;
        expect(
          before.where((c) => c.name == 'Makan & Minum • Pesanan Makanan'),
          isEmpty,
        );
        await _tap(tester, _save, repository: repository);
        final categories = (await tester.runAsync(
          () => repository.database.categoriesDao.watchActive().first,
        ))!;
        final selected = categories.singleWhere(
          (c) => c.name == 'Makan & Minum • Pesanan Makanan',
        );
        expect(
          (await _rows(tester, repository)).single.categoryId,
          selected.id,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('membatalkan pemilihan mempertahankan kategori draf', (
    tester,
  ) async {
    final repository = await _open(tester, _draft());
    await _tap(tester, find.byKey(const ValueKey('draft-category')));
    await _tap(tester, find.byTooltip('Tutup'));
    expect(find.text('Makan & Minum'), findsOneWidget);
    expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    expect(repository.saves, 0);
  });

  testWidgets('kategori milik pengguna ikut tampil dan ID yang ada digunakan', (
    tester,
  ) async {
    final repository = await _open(
      tester,
      _draft().copyWith(categoryId: null),
      extraCategories: [
        Category(
          id: 'custom',
          name: 'Usaha • Bahan Baku',
          kind: 'expense',
          createdAt: _date,
          updatedAt: _date,
          isDirty: false,
        ),
      ],
    );
    await _tap(tester, find.byKey(const ValueKey('draft-category')));
    await tester.enterText(
      find.widgetWithText(TextField, 'Cari kategori atau subkategori'),
      'bahan baku',
    );
    await tester.pumpAndSettle();
    expect(find.text('Usaha'), findsOneWidget);
    await _tap(tester, find.text('Bahan Baku'));
    await _tap(tester, _save, repository: repository);
    expect((await _rows(tester, repository)).single.categoryId, 'custom');
  });

  testWidgets('struk memiliki tombol teks OCR dan tetap menunggu konfirmasi', (
    tester,
  ) async {
    final repository = await _open(
      tester,
      _draft().copyWith(
        source: DraftSource.receipt,
        rawText: 'CAFE\nKOPI 35.000\nTOTAL 35.000',
        items: [const DraftItem(name: 'KOPI', amount: 35000)],
      ),
    );
    expect(repository.saves, 0);
    await _tap(tester, find.text('Detail input'));
    await _tap(tester, find.byKey(const ValueKey('draft-ocr-text')));
    expect(find.text('Teks OCR'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('CAFE\nKOPI 35.000\nTOTAL 35.000'),
      ),
      findsOneWidget,
    );
    await _tap(tester, find.text('Tutup'));
    expect(repository.saves, 0);
  });
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

  testWidgets(
    'low confidence asks manual completion and marks missing amount',
    (tester) async {
      await _open(tester, _draft(amount: null).copyWith(confidence: .59));
      expect(find.text('Lengkapi manual'), findsOneWidget);
      final field = tester.widget<TextField>(_amount);
      expect(field.decoration!.helperText, 'Isi jumlah uang.');
      expect(
        (field.decoration!.enabledBorder! as OutlineInputBorder)
            .borderSide
            .color,
        AppTheme.draftWarningColor,
      );
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      await tester.enterText(_amount, '35000');
      await tester.pumpAndSettle();
      expect(find.text('Isi jumlah uang.'), findsNothing);
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    },
  );

  for (final confidence in [.59, .6]) {
    testWidgets('manual completion message threshold $confidence', (
      tester,
    ) async {
      await _open(tester, _draft().copyWith(confidence: confidence));
      expect(
        find.text('Lengkapi manual'),
        confidence < .6 ? findsOneWidget : findsNothing,
      );
      // Confidence alone does not invalidate an otherwise complete draft.
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    });
  }

  testWidgets('desktop tetap dialog pada jendela sempit', (tester) async {
    await _open(
      tester,
      _draft(),
      size: const Size(500, 844),
      platform: TargetPlatform.windows,
    );
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('akun memuat atau kosong menonaktifkan simpan', (tester) async {
    final controller = StreamController<List<Account>>();
    addTearDown(controller.close);
    await _open(
      tester,
      _draft(),
      accountsStream: controller.stream,
      settle: false,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    controller.add([]);
    await tester.pumpAndSettle();
    expect(
      find.text('Belum ada akun. Tambahkan akun melalui tab Aset.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
  });

  testWidgets('gagal membaca pilihan memberi aksi coba lagi', (tester) async {
    await _open(
      tester,
      _draft(),
      accountsStream: Stream.error(StateError('unreadable')),
    );
    expect(
      find.text('Pilihan akun atau kategori belum dapat dimuat.'),
      findsOneWidget,
    );
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
  });

  testWidgets('menyimpan mencegah klik ganda dan menutup sebelum selesai', (
    tester,
  ) async {
    final repository = await _open(tester, _draft());
    repository.gate = Completer<void>();
    await tester.ensureVisible(_save);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pump();
    expect(repository.saves, 1);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Buang'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(DraftConfirmationSheet), findsOneWidget);
    repository.gate!.complete();
    await tester.runAsync(() => repository.lastSave!);
    await tester.pumpAndSettle();
    expect(repository.saves, 1);
    expect(await _rows(tester, repository), hasLength(1));
    expect(find.byType(DraftConfirmationSheet), findsNothing);
  });

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
      'Simpan nonaktif tanpa jumlah, aktif setelah diisi ${size.width}',
      (tester) async {
        final repository = await _open(
          tester,
          _draft(amount: null),
          size: size,
        );
        expect(
          size.width < AppTheme.sidebarBreakpoint
              ? find.byType(BottomSheet)
              : find.byType(Dialog),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(_save).onPressed, isNull);
        expect(find.text('Isi jumlah uang.'), findsOneWidget);
        expect(find.text('Makan siang 25000 dari Tunai'), findsNothing);
        await _tap(tester, find.text('Detail input'));
        expect(find.text('Makan siang 25000 dari Tunai'), findsOneWidget);
        await _tap(tester, find.text('Detail input'));
        await tester.ensureVisible(_amount);
        await tester.enterText(_amount, '1250000');
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(_amount).controller!.text, '1.250.000');
        expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
        expect(find.text('Isi jumlah uang.'), findsNothing);
        await _tap(tester, _save, repository: repository);
        expect(repository.saves, 1);
        final row = (await _rows(tester, repository)).single;
        expect(row.amount, 1250000);
        expect(row.type, 'expense');
        expect(row.accountId, 'cash');
        expect(row.categoryId, 'food');
        expect(row.note, 'Catatan draf');
        expect(row.occurredAt.toUtc(), _date);
        expect(row.isDirty, isTrue);
        expect(
          row.id,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
        expect(find.byType(DraftConfirmationSheet), findsNothing);
      },
    );
  }

  testWidgets('seluruh masalah menonaktifkan Simpan tanpa dialog error', (
    tester,
  ) async {
    await _open(
      tester,
      _draft(amount: 0).copyWith(
        accountId: null,
        categoryId: null,
        occurredAt: DateTime.now().add(const Duration(days: 2)),
      ),
    );
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    for (final message in [
      'Jumlah harus lebih dari Rp 0.',
      'Pilih akun transaksi.',
      'Pilih kategori transaksi.',
      'Tanggal maksimal 1 hari dari sekarang.',
    ]) {
      expect(find.text(message), findsOneWidget);
    }
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('transfer harus memakai dua akun berbeda', (tester) async {
    final repository = await _open(
      tester,
      _draft(type: TransactionType.transfer).copyWith(toAccountId: 'cash'),
    );
    expect(
      find.text('Akun tujuan harus berbeda dari akun asal.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    final destination = find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == 'Ke akun',
    );
    await _tap(tester, destination);
    await _tap(tester, find.text('Bank Jago').last);
    expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    expect(find.text('Kategori'), findsNothing);
    await _tap(tester, _save, repository: repository);
    final row = (await _rows(tester, repository)).single;
    expect(row.type, 'transfer');
    expect(row.toAccountId, 'bank');
    expect(row.categoryId, isNull);
    expect(row.recipientName, isNull);
    expect(repository.saves, 1);
  });

  testWidgets('item struk hanya baca dan peringatan parser bersifat bantuan', (
    tester,
  ) async {
    final repository = await _open(
      tester,
      _draft().copyWith(
        source: DraftSource.receipt,
        confidence: .45,
        items: [
          const DraftItem(name: 'Nasi goreng', amount: 20000),
          const DraftItem(name: 'Teh', amount: 5000),
        ],
        warnings: [
          const DraftWarning(message: 'Periksa total struk.'),
          const DraftWarning(
            field: DraftField.amount,
            message: 'Total belum pasti.',
          ),
        ],
      ),
    );
    await _tap(tester, find.text('Detail input'));
    expect(find.text('Keyakinan: Rendah (45%)'), findsOneWidget);
    expect(find.text('Nasi goreng'), findsOneWidget);
    expect(find.text('Rp 20.000'), findsOneWidget);
    expect(find.text('Periksa total struk.'), findsOneWidget);
    expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    await tester.enterText(_amount, '30000');
    await tester.pumpAndSettle();
    expect(find.text('Total belum pasti.'), findsNothing);
    await _tap(tester, find.text('Buang'));
    expect(repository.saves, 0);
    expect(await _rows(tester, repository), isEmpty);
  });

  for (final entry in {.8: 'Tinggi', .5: 'Sedang', .49: 'Rendah'}.entries) {
    testWidgets('chip keyakinan pada batas ${entry.key}', (tester) async {
      await _open(tester, _draft().copyWith(confidence: entry.key));
      await _tap(tester, find.text('Detail input'));
      expect(
        find.text('Keyakinan: ${entry.value} (${(entry.key * 100).round()}%)'),
        findsOneWidget,
      );
    });
  }

  for (final type in TransactionType.values) {
    testWidgets('Edit manual membawa data ${type.name}', (tester) async {
      final repository = await _open(tester, _draft(type: type));
      await tester.enterText(_amount, '75000');
      await tester.enterText(find.byType(TextField).last, 'Catatan terbaru');
      await _tap(tester, find.text('Edit manual'));
      expect(find.byType(DraftConfirmationSheet), findsNothing);
      expect(find.byType(TransactionEditor), findsOneWidget);
      final editor = tester.widget<TransactionEditor>(
        find.byType(TransactionEditor),
      );
      expect(editor.initialDraft!.amount, 75000);
      expect(editor.originalDraft!.amount, 25000);
      expect(editor.initialDraft!.type, type);
      expect(editor.initialDraft!.note, 'Catatan terbaru');
      expect(editor.initialDraft!.occurredAt, _date);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '75.000',
      );
      expect(repository.saves, 0);
      await _tap(tester, find.text('Simpan transaksi'), repository: repository);
      final row = (await _rows(tester, repository)).single;
      expect(row.amount, 75000);
      expect(row.type, type.name);
      expect(row.accountId, 'cash');
      expect(row.toAccountId, type == TransactionType.transfer ? 'bank' : null);
      expect(
        row.categoryId,
        type == TransactionType.transfer
            ? null
            : type == TransactionType.income
            ? 'salary'
            : 'food',
      );
      expect(row.note, 'Catatan terbaru');
      expect(row.occurredAt.toUtc(), _date);
      expect(repository.saves, 1);
      final learned = (await tester.runAsync(
        () => repository.database
            .select(repository.database.quickInputMemory)
            .get(),
      ))!;
      expect(learned.map((m) => m.keyword), contains('catatan terbaru'));
      expect(learned.every((m) => m.count == 1), isTrue);
    });
  }

  testWidgets(
    'gagal simpan memberi bantuan dan mempertahankan draf untuk dicoba ulang',
    (tester) async {
      final repository = await _open(tester, _draft());
      repository.failNext = true;
      await _tap(tester, _save, repository: repository);
      expect(
        find.text('Transaksi belum tersimpan. Coba simpan kembali.'),
        findsOneWidget,
      );
      expect(find.byType(DraftConfirmationSheet), findsOneWidget);
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
      await _tap(tester, _save, repository: repository);
      expect(repository.saves, 2);
      expect(await _rows(tester, repository), hasLength(1));
    },
  );

  testWidgets(
    'akun asing tidak boleh disimpan walau validator domain memiliki ID',
    (tester) async {
      await _open(tester, _draft().copyWith(accountId: 'archived-account'));
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      expect(find.text('Pilih akun transaksi.'), findsOneWidget);
    },
  );

  testWidgets('kategori berbeda jenis harus dipilih ulang saat ganti jenis', (
    tester,
  ) async {
    await _open(tester, _draft());
    await _tap(tester, find.text('Masuk'));
    expect(find.text('Menuju Akun'), findsOneWidget);
    expect(find.text('Pilih kategori transaksi.'), findsOneWidget);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
  });

  testWidgets('font 200 persen di layar kecil tetap dapat digulir', (
    tester,
  ) async {
    await _open(
      tester,
      _draft(amount: null),
      size: const Size(390, 844),
      textScale: 2,
    );
    await tester.ensureVisible(_amount);
    await tester.enterText(_amount, '25000');
    await tester.ensureVisible(_save);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mengoreksi semua isian menyimpan nilai terbaru dan tanggal UTC',
    (tester) async {
      final repository = await _open(tester, _draft());
      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is InputDecorator && widget.decoration.labelText == label,
      );
      await _tap(tester, find.text('Masuk'));
      await _tap(tester, field('Menuju Akun'));
      await _tap(tester, find.text('Bank Jago').last);
      await _tap(tester, field('Kategori'));
      expect(find.text('Pilih kategori pemasukan'), findsOneWidget);
      await _tap(tester, find.text('Pemasukan'));
      await _tap(tester, find.text('Gaji'));
      await tester.enterText(_amount, '90000');
      await tester.enterText(
        find.byType(TextField).last,
        'Gaji yang dikoreksi',
      );
      await _tap(tester, field('Tanggal'));
      final localizations = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)),
      );
      await _tap(tester, find.byIcon(Icons.edit_outlined));
      final selected = DateTime(2020, 10, 9, 21, 35);
      await tester.enterText(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextFormField),
        ),
        localizations.formatCompactDate(selected),
      );
      await _tap(tester, find.text(localizations.okButtonLabel));
      final timeInputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(timeInputs.at(0), '21');
      await tester.enterText(timeInputs.at(1), '35');
      await _tap(tester, find.text(localizations.okButtonLabel));
      await _tap(tester, _save, repository: repository);
      final row = (await _rows(tester, repository)).single;
      expect(row.type, 'income');
      expect(row.amount, 90000);
      expect(row.accountId, 'bank');
      expect(row.categoryId, 'salary');
      expect(row.note, 'Gaji yang dikoreksi');
      expect(row.occurredAt.toUtc(), selected.toUtc());
      expect(row.toAccountId, isNull);
    },
  );
}
