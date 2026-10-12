import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/app/mvp_screens.dart' show TransactionEditor;
import 'package:ledgy/core/database/app_database.dart';
import 'package:ledgy/core/providers/app_providers.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/core/widgets/empty_state.dart';
import 'package:ledgy/core/widgets/money_text.dart';
import 'package:ledgy/features/categories/data/repositories/categories_repository_impl.dart';
import 'package:ledgy/features/quick_input/data/quick_input_categories.dart';
import 'package:ledgy/features/quick_input/domain/parser/draft_parser.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_context.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_pipeline.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';
import 'package:ledgy/features/quick_input/domain/voice_input_backend.dart';
import 'package:ledgy/features/quick_input/presentation/draft_confirmation_sheet.dart';
import 'package:ledgy/features/quick_input/presentation/quick_input_bar.dart';
import 'package:ledgy/features/quick_input/presentation/quick_input_providers.dart';
import 'package:ledgy/features/transactions/data/repositories/transactions_repository_impl.dart';

import 'support/fake_voice_backend.dart';
import 'support/fake_parser_failures.dart';

final _now = DateTime.utc(2020, 10, 8, 10);
final _accounts = [
  for (final name in ['Tunai', 'BCA', 'GoPay', 'DANA'])
    Account(
      id: name.toLowerCase(),
      name: name,
      initialBalance: 0,
      createdAt: _now,
      updatedAt: _now,
      isDirty: false,
    ),
];
final _categories = [
  for (final entry in [
    ('food', 'Makanan', 'expense'),
    ('transport', 'Transport', 'expense'),
    ('salary', 'Gaji', 'income'),
  ])
    Category(
      id: entry.$1,
      name: entry.$2,
      kind: entry.$3,
      createdAt: _now,
      updatedAt: _now,
      isDirty: false,
    ),
];
ParserContext _context() => ParserContext(
  clock: FixedClock(_now),
  lastAccountId: 'tunai',
  accounts: [
    for (final account in _accounts)
      ParserAccount(id: account.id, name: account.name),
  ],
  categories: [
    for (final category in _categories)
      ParserCategory(
        id: category.id,
        name: category.name,
        type: TransactionType.values.byName(category.kind),
      ),
  ],
);

class _Repository extends TransactionsRepository {
  _Repository(this.db) : super(db.transactionsDao);
  final AppDatabase db;
  Future<void>? lastSave;
  int saves = 0;
  @override
  Future<void> save(TransactionsCompanion value) {
    saves++;
    return lastSave = super.save(value);
  }
}

class _InjectedParser implements DraftParser {
  String? text;
  @override
  Future<List<TransactionDraft>> parse(String text, ParserContext ctx) async {
    this.text = text;
    return [
      TransactionDraft(
        type: TransactionType.expense,
        amount: 61000,
        accountId: 'tunai',
        categoryId: 'food',
        occurredAt: ctx.clock.now(),
        confidence: .9,
        rawText: 'Pipeline result',
      ),
    ];
  }
}

Finder get _input => find.byKey(const ValueKey('quick-input-text'));
Finder get _mic => find.byKey(const ValueKey('quick-input-microphone'));
Finder get _submit => find.byKey(const ValueKey('quick-input-submit'));
Finder get _save => find.byKey(const ValueKey('draft-save'));

Future<_Repository> _open(
  WidgetTester tester,
  FakeVoiceBackend voice, {
  TargetPlatform platform = TargetPlatform.windows,
  bool launcher = false,
  bool failingContext = false,
  double textScale = 1,
  ParserPipeline? pipeline,
  bool useCatalog = false,
  FakeParserFailures? failures,
}) async {
  tester.view.physicalSize = platform == TargetPlatform.android
      ? const Size(360, 900)
      : const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = _Repository(db);
  final catalog = QuickInputCategories(CategoriesRepository(db.categoriesDao));
  await tester.runAsync(() => db.customSelect('SELECT 1').get());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        if (failures != null)
          parserFailureRepositoryProvider.overrideWithValue(failures),
        transactionsRepositoryProvider.overrideWithValue(repo),
        voiceInputBackendProvider.overrideWithValue(voice),
        if (useCatalog) quickInputCategoriesProvider.overrideWithValue(catalog),
        if (pipeline != null)
          parserPipelineProvider.overrideWithValue(pipeline),
        parserContextProvider.overrideWith((ref) async {
          if (failingContext) throw StateError('sensitive details');
          if (useCatalog) {
            final choices = catalog.preview(
              await ref.watch(categoriesProvider.future),
            );
            return ParserContext(
              clock: FixedClock(_now),
              accounts: _context().accounts,
              lastAccountId: 'tunai',
              categories: [
                for (final category in choices)
                  ParserCategory(
                    id: category.id,
                    name: category.name,
                    type: TransactionType.values.byName(category.kind),
                  ),
              ],
            );
          }
          return _context();
        }),
        accountsProvider.overrideWith((ref) => Stream.value(_accounts)),
        categoriesProvider.overrideWith((ref) => Stream.value(_categories)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: QuickInputShortcutScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: launcher
                  ? const DashboardQuickInput()
                  : const QuickInputBar(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(_input, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> _persist(WidgetTester tester, _Repository repo) async {
  await tester.runAsync(() async {
    await tester.tap(_save);
    await repo.lastSave;
    await repo.db.customSelect('SELECT 1').get();
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  for (final action in ['Simpan', 'Edit manual', 'Buang']) {
    testWidgets('minum kopi chooses Cafe / Warkop with $action', (
      tester,
    ) async {
      final repo = await _open(tester, FakeVoiceBackend(), useCatalog: true);
      await _send(tester, 'minum kopi 35rb via GoPay');
      expect(find.text('Makan & Minum • Cafe / Warkop'), findsOneWidget);
      final before = await tester.runAsync(
        () => repo.db.categoriesDao.watchActive().first,
      );
      expect(before!.where((c) => c.name.contains('Cafe / Warkop')), isEmpty);
      if (action == 'Buang') {
        await tester.tap(find.text('Buang'));
        await tester.pumpAndSettle();
        expect(repo.saves, 0);
      } else if (action == 'Edit manual') {
        await tester.tap(find.text('Edit manual'));
        await tester.pumpAndSettle();
        expect(find.text('Makan & Minum • Cafe / Warkop'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Simpan transaksi'));
          await repo.lastSave;
          await repo.db.customSelect('SELECT 1').get();
        });
        await tester.pumpAndSettle();
        expect(repo.saves, 1);
      } else {
        await _persist(tester, repo);
        expect(repo.saves, 1);
      }
      final after = await tester.runAsync(
        () => repo.db.categoriesDao.watchActive().first,
      );
      final cafes = after!
          .where((c) => c.name.contains('Cafe / Warkop'))
          .toList();
      expect(cafes.length, action == 'Buang' ? 0 : 1);
      if (action != 'Buang') {
        final rows = await tester.runAsync(
          () => repo.db.transactionsDao.watchActive().first,
        );
        expect(rows!.single.categoryId, cafes.single.id);
      }
    });
  }
  for (final voiceInput in [false, true]) {
    testWidgets(
      'UI uses injected pipeline for ${voiceInput ? 'voice' : 'text'}',
      (tester) async {
        final parser = _InjectedParser();
        final voice = FakeVoiceBackend();
        final failures = FakeParserFailures()..active = true;
        final repo = await _open(
          tester,
          voice,
          pipeline: ParserPipeline(ruleBasedParser: parser),
          failures: failures,
        );
        const input = 'makan tiga puluh lima ribu pakai go pay';
        if (voiceInput) {
          await tester.tap(_mic);
          await tester.pump();
          voice.emit(input, finalResult: true);
          await tester.pumpAndSettle();
        } else {
          await _send(tester, input);
        }
        expect(
          parser.text,
          voiceInput ? 'makan tiga puluh lima ribu pakai gopay' : input,
        );
        final draft = tester
            .widget<DraftConfirmationSheet>(find.byType(DraftConfirmationSheet))
            .draft;
        expect(draft.amount, 61000);
        expect(draft.source, voiceInput ? DraftSource.voice : DraftSource.text);
        expect(repo.saves, 0);
        expect(failures.records, voiceInput ? 0 : 1);
        expect(failures.rows, voiceInput ? isEmpty : [input]);
      },
    );
  }
  testWidgets('Enter ketik membuka konfirmasi, lalu repository simpan sekali', (
    tester,
  ) async {
    final repo = await _open(tester, FakeVoiceBackend());
    await _send(tester, 'makan 35 ribu pakai GoPay');
    expect(find.byType(DraftConfirmationSheet), findsOneWidget);
    expect(
      tester
          .widget<DraftConfirmationSheet>(find.byType(DraftConfirmationSheet))
          .draft
          .amount,
      35000,
    );
    expect(repo.saves, 0);
    await _persist(tester, repo);
    expect(repo.saves, 1);
    final rows = await tester.runAsync(
      () => repo.db.select(repo.db.transactions).get(),
    );
    expect(rows!.single.amount, 35000);
    expect(rows.single.accountId, 'gopay');
    expect(rows.single.note, 'makan');
    expect(find.text('Transaksi tersimpan.'), findsOneWidget);
  });
  testWidgets('beberapa draf disimpan satu per satu, tidak ada simpan semua', (
    tester,
  ) async {
    final repo = await _open(tester, FakeVoiceBackend());
    await _send(tester, 'makan 20rb via GoPay; gaji 8 juta ke BCA');
    expect(find.byType(DraftConfirmationSheet), findsNothing);
    expect(
      find.text('2 draf · tinjau dan simpan satu per satu'),
      findsOneWidget,
    );
    expect(repo.saves, 0);
    await tester.tap(find.byKey(const ValueKey('quick-input-review-0')));
    await tester.pumpAndSettle();
    await _persist(tester, repo);
    expect(repo.saves, 1);
    expect(find.text('Tersimpan'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('quick-input-review-1')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('quick-input-review-1')));
    await tester.pumpAndSettle();
    await _persist(tester, repo);
    expect(repo.saves, 2);
    expect(find.text('Tersimpan'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('quick-input-clear')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_input).enabled, isTrue);
  });
  testWidgets(
    'batch lewat Edit manual ditandai tersimpan dan tidak bisa disimpan lagi',
    (tester) async {
      final repo = await _open(tester, FakeVoiceBackend());
      await _send(tester, 'makan 20rb via GoPay; bensin 50rb');
      await tester.tap(find.byKey(const ValueKey('quick-input-review-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit manual'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionEditor), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Simpan transaksi'));
        await repo.lastSave;
        await repo.db.customSelect('SELECT 1').get();
      });
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(find.text('Tersimpan'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-input-review-0')), findsNothing);
    },
  );
  testWidgets(
    'Buang satu draf tidak menulis ledger dan tidak membuang draf lain',
    (tester) async {
      final repo = await _open(tester, FakeVoiceBackend());
      await _send(tester, 'makan 20rb via GoPay; bensin 50rb');
      await tester.tap(find.byKey(const ValueKey('quick-input-review-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buang'));
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(find.text('Dibuang'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick-input-review-1')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'suara interim RingProgress, final otomatis masuk jalur konfirmasi',
    (tester) async {
      final voice = FakeVoiceBackend();
      final repo = await _open(tester, voice);
      await tester.tap(_mic);
      await tester.pump();
      expect(find.byType(RingProgress), findsOneWidget);
      voice.emit('makan siang tiga');
      await tester.pump();
      expect(find.text('makan siang tiga'), findsOneWidget);
      expect(find.byType(DraftConfirmationSheet), findsNothing);
      voice.emit(
        'makan siang tiga puluh lima ribu rupiah pakai go pay',
        finalResult: true,
      );
      await tester.pumpAndSettle();
      final draft = tester
          .widget<DraftConfirmationSheet>(find.byType(DraftConfirmationSheet))
          .draft;
      expect(draft.source, DraftSource.voice);
      expect(draft.amount, 35000);
      expect(draft.accountId, 'gopay');
      expect(
        draft.rawText,
        'makan siang tiga puluh lima ribu rupiah pakai go pay',
      );
      expect(find.byType(RingProgress), findsNothing);
      expect(repo.saves, 0);
    },
  );
  testWidgets('izin permanen diblokir ada petunjuk dan tombol pengaturan', (
    tester,
  ) async {
    final voice = FakeVoiceBackend()..access = MicrophoneAccess.blocked;
    await _open(tester, voice);
    await tester.tap(_mic);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pengaturan sistem'), findsOneWidget);
    await tester.tap(find.text('Buka pengaturan'));
    await tester.pumpAndSettle();
    expect(voice.settings, 1);
    expect(voice.listenedLocale, isNull);
  });
  testWidgets(
    'locale Indonesia hilang menjelaskan unduh dan ketik tetap aktif',
    (tester) async {
      final voice = FakeVoiceBackend()..languages = ['en_US'];
      await _open(tester, voice);
      await tester.tap(_mic);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unduh paket Bahasa Indonesia'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(_input).enabled, isTrue);
      expect(voice.listenedLocale, isNull);
      await tester.enterText(_input, 'makan 35rb via GoPay');
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(find.byType(DraftConfirmationSheet), findsOneWidget);
    },
  );
  testWidgets('platform non-Android menyembunyikan kamera dan memberi pesan', (
    tester,
  ) async {
    await _open(tester, FakeVoiceBackend()..supportedPlatform = false);
    expect(_mic, findsNothing);
    expect(find.byKey(const ValueKey('quick-input-camera')), findsNothing);
    expect(find.text('Pemindaian struk tersedia di Android'), findsOneWidget);
  });
  testWidgets('Ctrl+K desktop memfokuskan kolom Beranda yang sudah tampil', (
    tester,
  ) async {
    await _open(tester, FakeVoiceBackend(), launcher: true);
    expect(_input, findsOneWidget);
    expect(find.byKey(const ValueKey('quick-input-launcher')), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_input, findsOneWidget);
    expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
    expect(find.byType(Dialog), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_input, findsOneWidget);
  });
  testWidgets(
    'Beranda desktop langsung menerima ketikan dan membuka konfirmasi',
    (tester) async {
      await _open(tester, FakeVoiceBackend(), launcher: true);
      expect(_input, findsOneWidget);
      expect(_mic, findsOneWidget);
      expect(_submit, findsOneWidget);
      expect(find.text('Input cepat'), findsNothing);
      await _send(tester, 'makan 35rb pakai GoPay');
      expect(find.byType(DraftConfirmationSheet), findsOneWidget);
    },
  );
  testWidgets('mobile inline dan font 200% tidak overflow', (tester) async {
    await _open(
      tester,
      FakeVoiceBackend(),
      platform: TargetPlatform.android,
      launcher: true,
      textScale: 2,
    );
    expect(_input, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('tanpa jumlah tetap konfirmasi dengan Simpan nonaktif', (
    tester,
  ) async {
    await _open(tester, FakeVoiceBackend());
    await _send(tester, 'makan via GoPay');
    expect(find.byType(MoneyText), findsOneWidget);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
  });
  testWidgets('context gagal memberi bantuan tanpa membocorkan exception', (
    tester,
  ) async {
    await _open(tester, FakeVoiceBackend(), failingContext: true);
    await _send(tester, 'makan 35000');
    expect(find.textContaining('Coba lagi.'), findsOneWidget);
    expect(find.textContaining('sensitive details'), findsNothing);
    expect(tester.widget<TextField>(_input).enabled, isTrue);
  });
  testWidgets(
    'background atau tutup bar menghentikan mikrofon dan mengabaikan hasil terlambat',
    (tester) async {
      final voice = FakeVoiceBackend();
      await _open(tester, voice);
      await tester.tap(_mic);
      await tester.pump();
      voice.emit('sementara');
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      voice.emit('makan 35000', finalResult: true);
      await tester.pumpAndSettle();
      expect(find.byType(DraftConfirmationSheet), findsNothing);
      expect(find.text('sementara'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      voice.emit('gaji 8000000', finalResult: true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(voice.cancels, greaterThan(0));
    },
  );
}
