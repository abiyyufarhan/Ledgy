import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/quick_input/domain/parser/draft_parser.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_context.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_pipeline.dart';
import 'package:ledgy/features/quick_input/domain/parser/rule_based_parser.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

final _ctx = ParserContext(
  clock: FixedClock(DateTime.utc(2026, 10, 8, 10)),
  accounts: [ParserAccount(id: 'cash', name: 'Tunai')],
  categories: [
    const ParserCategory(
      id: 'food',
      name: 'Makanan',
      type: TransactionType.expense,
    ),
  ],
  lastAccountId: 'cash',
);

TransactionDraft _draft({double confidence = .9, int? amount = 35000}) =>
    TransactionDraft(
      type: TransactionType.expense,
      confidence: confidence,
      amount: amount,
      accountId: 'cash',
      categoryId: 'food',
      occurredAt: _ctx.clock.now(),
    );

class _Rules implements DraftParser {
  _Rules(this.drafts);
  final List<TransactionDraft> drafts;
  int calls = 0;
  @override
  Future<List<TransactionDraft>> parse(String text, ParserContext ctx) async {
    calls++;
    return drafts;
  }
}

class _Fallback implements FallbackParser {
  _Fallback(this.result);
  final List<TransactionDraft> result;
  int calls = 0;
  String? text;
  ParserContext? context;
  bool fail = false;
  @override
  Future<List<TransactionDraft>> parse(String text, ParserContext ctx) async {
    calls++;
    this.text = text;
    context = ctx;
    if (fail) throw StateError('fallback unavailable');
    return result;
  }
}

// Test-only stand-in for a future transport. Production has no such parser.
class _NetworkFallback implements FallbackParser {
  int calls = 0;
  @override
  Future<List<TransactionDraft>> parse(String text, ParserContext ctx) async {
    calls++;
    final client = HttpClient();
    client.close(force: true);
    throw StateError('The disabled fallback must never reach a transport.');
  }
}

void main() {
  test(
    'Tier 0 defaults to rules with no fallback and a disabled flag',
    () async {
      const pipeline = ParserPipeline();
      expect(pipeline.aiFallbackEnabled, isFalse);
      expect(pipeline.fallbackParser, isNull);
      final drafts = await pipeline.parse('makan 35rb pakai Tunai', _ctx);
      expect(drafts.single.amount, 35000);
      expect(drafts.single.accountId, 'cash');
      expect(drafts.single.categoryId, 'food');
    },
  );

  test(
    'flag off never invokes fallback or constructs a network client',
    () async {
      var networkAttempts = 0;
      final fallback = _NetworkFallback();
      await HttpOverrides.runZoned(
        () async {
          for (final draft in [
            _draft(confidence: .59),
            _draft(confidence: .9, amount: null),
            _draft(confidence: 0, amount: null),
          ]) {
            final rules = _Rules([draft]);
            final pipeline = ParserPipeline(
              ruleBasedParser: rules,
              fallbackParser: fallback,
              aiFallbackEnabled: false,
            );
            expect((await pipeline.parse('unclear', _ctx)).single, same(draft));
            expect(rules.calls, 1);
            expect(
              (await pipeline.inspect('unclear', _ctx)).drafts.single,
              same(draft),
            );
            expect(rules.calls, 2);
          }
          // Also exercise the real local parser for missing/ambiguous/batch input.
          final pipeline = ParserPipeline(fallbackParser: fallback);
          for (final text in [
            'makan tanpa jumlah',
            'belanja 1,000 juta',
            'makan 20rb; bensin 50rb',
          ]) {
            expect(await pipeline.parse(text, _ctx), isNotEmpty);
            expect((await pipeline.inspect(text, _ctx)).drafts, isNotEmpty);
          }
        },
        createHttpClient: (context) {
          networkAttempts++;
          throw StateError('Network disabled by test guard.');
        },
      );
      expect(fallback.calls, 0);
      expect(networkAttempts, 0);
    },
  );

  for (final confidence in [.59, .6, .8]) {
    test('enabled fallback confidence boundary $confidence', () async {
      final draft = _draft(confidence: confidence);
      final corrected = _draft(amount: 45000);
      final fallback = _Fallback([corrected]);
      final pipeline = ParserPipeline(
        ruleBasedParser: _Rules([draft]),
        fallbackParser: fallback,
        aiFallbackEnabled: true,
      );
      final result = await pipeline.parse('original text', _ctx);
      expect(fallback.calls, confidence < .6 ? 1 : 0);
      expect(result.single, same(confidence < .6 ? corrected : draft));
      if (confidence < .6) {
        expect(fallback.text, 'original text');
        expect(fallback.context, same(_ctx));
      }
    });
  }

  test(
    'missing amount triggers enabled fallback even at high confidence',
    () async {
      final fallback = _Fallback([_draft()]);
      await ParserPipeline(
        ruleBasedParser: _Rules([_draft(amount: null)]),
        fallbackParser: fallback,
        aiFallbackEnabled: true,
      ).parse('missing amount', _ctx);
      expect(fallback.calls, 1);
    },
  );

  test('null slot still retains local draft when flag is enabled', () async {
    final draft = _draft(amount: null);
    final result = await ParserPipeline(
      ruleBasedParser: _Rules([draft]),
      aiFallbackEnabled: true,
    ).parse('unclear', _ctx);
    expect(result.single, same(draft));
  });

  test(
    'eligible batch invokes fallback once for the original sentence',
    () async {
      final fallback = _Fallback([
        _draft(amount: 20000),
        _draft(amount: 50000),
      ]);
      final result = await ParserPipeline(
        ruleBasedParser: _Rules([_draft(), _draft(confidence: .2)]),
        fallbackParser: fallback,
        aiFallbackEnabled: true,
      ).parse('makan 20rb; bensin 50rb', _ctx);
      expect(fallback.calls, 1);
      expect(fallback.text, 'makan 20rb; bensin 50rb');
      expect(result.map((draft) => draft.amount), [20000, 50000]);
      expect(() => result.clear(), throwsUnsupportedError);
    },
  );

  for (final fail in [false, true]) {
    test(
      'empty or failed optional fallback keeps local drafts (fail=$fail)',
      () async {
        final draft = _draft(confidence: .3);
        final fallback = _Fallback([])..fail = fail;
        final result = await ParserPipeline(
          ruleBasedParser: _Rules([draft]),
          fallbackParser: fallback,
          aiFallbackEnabled: true,
        ).parse('unclear', _ctx);
        expect(result.single, same(draft));
        expect(fallback.calls, 1);
      },
    );
  }

  test(
    'RuleBasedParser adapter preserves several drafts and UTC dates',
    () async {
      final drafts = await const RuleBasedParser().parse(
        'makan 20rb via Tunai; makan 35rb via Tunai',
        _ctx,
      );
      expect(drafts.map((draft) => draft.amount), [20000, 35000]);
      expect(drafts.every((draft) => draft.occurredAt!.isUtc), isTrue);
    },
  );
}
