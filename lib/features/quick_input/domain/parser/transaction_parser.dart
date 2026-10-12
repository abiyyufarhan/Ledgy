import '../transaction_draft.dart';
import 'account_matcher.dart';
import 'amount_parser.dart';
import 'category_matcher.dart';
import 'date_parser.dart';
import 'normalizer.dart';
import 'parse_span.dart';
import 'parser_context.dart';
import 'type_detector.dart';
import 'parser_inspection.dart';

export 'parser_context.dart';

/// Single-draft API. Use parseMany to retain every transaction in a sentence.
TransactionDraft parse(String text, ParserContext ctx) {
  final drafts = parseMany(text, ctx);
  if (drafts.length == 1) return drafts.single;
  final first = drafts.first;
  return first.copyWith(
    rawText: text,
    confidence: (first.confidence - .1).clamp(0, 1).toDouble(),
    warnings: [
      ...first.warnings,
      const DraftWarning(
        code: 'MULTIPLE_TRANSACTIONS',
        message: 'Kalimat berisi beberapa transaksi. Gunakan konfirmasi terpisah untuk setiap transaksi.',
      ),
    ],
  );
}

List<TransactionDraft> parseMany(
  String text,
  ParserContext ctx, {
  ParserObserver? observer,
}) {
  // A batch shares one calendar instant even if parsing crosses midnight.
  ctx = ParserContext(
    clock: FixedClock(ctx.clock.now()),
    accounts: ctx.accounts,
    categories: ctx.categories,
    memory: ctx.memory,
    lastAccountId: ctx.lastAccountId,
  );
  final chunks = <String>[];
  var start = 0;
  for (final match in RegExp(
    r',|;|\s+dan\s+',
    caseSensitive: false,
  ).allMatches(text)) {
    final numericComma =
        match.group(0) == ',' &&
        match.start > 0 &&
        match.end < text.length &&
        RegExp(r'\d').hasMatch(text[match.start - 1]) &&
        RegExp(r'\d').hasMatch(text[match.end]);
    if (numericComma) continue;
    chunks.add(text.substring(start, match.start).trim());
    start = match.end;
  }
  chunks.add(text.substring(start).trim());
  observer?.call(ParserStep('Pemisahan', '${chunks.length} potongan kalimat'));
  if (chunks.length == 1) {
    return List.unmodifiable([_parseOne(text, ctx, observer)]);
  }
  final drafts = chunks
      .map((chunk) => _parseOne(chunk, ctx, observer))
      .toList();
  if (drafts.every((draft) => draft.amount != null)) {
    return List.unmodifiable(drafts);
  }
  final single = _parseOne(text, ctx, observer);
  observer?.call(
    const ParserStep(
      'Pemisahan dibatalkan',
      'Tidak semua potongan memiliki jumlah; INCOMPLETE_SPLIT',
    ),
  );
  return List.unmodifiable([
    single.copyWith(
      confidence: (single.confidence - .1).clamp(0, 1).toDouble(),
      warnings: [
        ...single.warnings,
        const DraftWarning(
          code: 'INCOMPLETE_SPLIT',
          message: 'Potongan kalimat tidak semuanya memiliki jumlah. Periksa apakah ini satu transaksi.',
        ),
      ],
    ),
  ]);
}

TransactionDraft _parseOne(
  String raw,
  ParserContext ctx, [
  ParserObserver? observer,
]) {
  final text = const Normalizer().normalize(raw);
  observer?.call(ParserStep('Normalisasi', text));
  final dates = const DateParser().parse(text, ctx.clock);
  observer?.call(
    ParserStep(
      'Tanggal',
      '${dates.occurredAt?.toIso8601String() ?? "kosong"} ${dates.warnings.map((w) => w.code).join(', ')}',
    ),
  );
  const detector = TypeDetector();
  const matcher = AccountMatcher();
  final transferHint =
      detector.isTransfer(text) ||
      (containsPhrase(text, 'top up') && matcher.mentionCount(text, ctx) >= 2);
  final account = matcher.match(text, ctx, transfer: transferHint);
  observer?.call(
    ParserStep(
      'Akun',
      '${account.accountId ?? "kosong"} → ${account.toAccountId ?? "—"}; cocok=${account.matched}',
    ),
  );
  final amount = const AmountParser().parse(
    text,
    excluded: [...dates.spans, ...account.spans],
  );
  observer?.call(
    ParserStep(
      'Jumlah',
      '${amount.amount ?? "kosong"} rupiah; jelas=${amount.clear}; ${amount.warnings.map((w) => w.code).join(', ')}',
    ),
  );
  final note =
      removeSpans(text, [...amount.spans, ...dates.spans, ...account.spans])
          .replaceAll(Normalizer.moneyToken, '')
          .replaceAll(RegExp(r'^[\s,;]+|[\s,;]+$'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  final type = detector.detect(text, hasOtherAccount: transferHint);
  observer?.call(
    ParserStep('Jenis', '${type.type.name}; kata kunci=${type.matched}'),
  );
  final category = const CategoryMatcher().match(note, ctx, type.type);
  observer?.call(
    ParserStep(
      'Kategori dan catatan',
      '${category.categoryId ?? "kosong"}; $note',
    ),
  );
  final warnings = [
    ...amount.warnings,
    ...dates.warnings,
    ...account.warnings,
    ...category.warnings,
  ];
  // Confidence uses integer points; only the final 0–1 score is floating point.
  final points =
      30 +
      (amount.clear ? 30 : 0) +
      (type.matched ? 15 : 0) +
      (account.matched ? 10 : 0) +
      (category.categoryId == null ? 0 : 10) -
      warnings.length * 10;
  observer?.call(
    ParserStep(
      'Confidence',
      '30 dasar + ${amount.clear ? 30 : 0} jumlah + ${type.matched ? 15 : 0} jenis + ${account.matched ? 10 : 0} akun + ${category.categoryId == null ? 0 : 10} kategori - ${warnings.length * 10} warning = ${points.clamp(0, 100)}%; ${warnings.map((w) => w.code).join(', ')}',
    ),
  );
  return TransactionDraft(
    type: type.type,
    amount: amount.amount,
    accountId: account.accountId,
    toAccountId: type.type == TransactionType.transfer
        ? account.toAccountId
        : null,
    categoryId: category.categoryId,
    occurredAt: dates.occurredAt,
    note: note.isEmpty ? null : note,
    rawText: raw,
    source: DraftSource.text,
    warnings: warnings,
    confidence: points.clamp(0, 100) / 100,
  );
}
