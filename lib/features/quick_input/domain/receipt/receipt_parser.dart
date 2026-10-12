import '../transaction_draft.dart';
import '../parser/amount_parser.dart';
import '../parser/category_matcher.dart';
import '../parser/normalizer.dart';
import '../parser/parser_context.dart';
import 'ocr_line.dart';

final class _Price {
  const _Price(
    this.start,
    this.end,
    this.amount,
    this.corrected,
    this.ambiguous,
  );
  final int start, end, amount;
  final bool corrected, ambiguous;
}

/// Pure Dart. OCR geometry and parsing never perform I/O or write transactions.
final class ReceiptParser {
  const ReceiptParser();
  static final _total = RegExp(
    r'\b(GRAND\s+TOTAL|TOTAL\s+BAYAR|TOTAL|JUMLAH|TAGIHAN|NETTO)\b',
    caseSensitive: false,
  );
  static final _notTotal = RegExp(
    r'\b(SUB\s*TOTAL|TOTAL\s+(ITEM|QTY)|JUMLAH\s+(ITEM|QTY))\b',
    caseSensitive: false,
  );
  static final _nonItem = RegExp(
    r'\b(SUB\s*TOTAL|TOTAL|JUMLAH|TAGIHAN|NETTO|PPN|PAJAK|TAX|SERVICE|DISKON|DISCOUNT|TUNAI|CASH|KEMBALI|CHANGE|BAYAR|DEBIT|QRIS|KARTU|GOPAY|OVO|DANA)\b',
    caseSensitive: false,
  );
  static final _address = RegExp(
    r'\b(JL\.?|JALAN|NPWP|TELP|TELEPON|KASIR|STRUK|RECEIPT|NO\.?|TERIMA\s+KASIH)\b',
    caseSensitive: false,
  );
  // Boundaries deliberately exclude alphabetic words: TOTAL, BAKSO, etc.
  static final _numeric = RegExp(
    r'(?<![A-Za-z0-9])(?:Rp\.?\s*)?[0-9OIlSB]+(?:[.,][0-9OIlSB]+)*(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  static String correctNumericToken(String token) => token
      .replaceAll('O', '0')
      .replaceAll('o', '0')
      .replaceAll('I', '1')
      .replaceAll('l', '1')
      .replaceAll('S', '5')
      .replaceAll('s', '5')
      .replaceAll('B', '8')
      .replaceAll('b', '8');

  String _numericDates(String text) => text.replaceAllMapped(
    RegExp(
      r'\b[0-9OIlSB]{1,4}[/\-][0-9OIlSB]{1,2}[/\-][0-9OIlSB]{1,4}\b|\b[0-9OIlSB]{1,2}:[0-9OIlSB]{2}\b',
    ),
    (match) => RegExp(r'\d').hasMatch(match.group(0)!)
        ? correctNumericToken(match.group(0)!)
        : match.group(0)!,
  );

  List<_Price> _prices(String text) {
    final result = <_Price>[];
    for (final m in _numeric.allMatches(text)) {
      final raw = m.group(0)!;
      if (!RegExp(r'\d').hasMatch(raw)) continue;
      var token = correctNumericToken(
        raw.replaceFirst(RegExp(r'^rp\.?\s*', caseSensitive: false), ''),
      );
      // Indonesian receipts print integer rupiah followed by two zero cents.
      token = token.replaceFirst(RegExp(r'[.,]00$'), '');
      if (m.end < text.length && RegExp(r'[%/:\-]').hasMatch(text[m.end])) {
        continue;
      }
      if (m.start > 0 &&
          (RegExp(r'[/:]').hasMatch(text[m.start - 1]) ||
              text[m.start - 1] == '-' &&
                  m.start > 1 &&
                  RegExp(r'\d').hasMatch(text[m.start - 2]))) {
        continue;
      }
      final parsed = const AmountParser().parse(
        '${Normalizer.moneyToken} $token',
      );
      final amount = parsed.amount;
      if (amount != null && amount > 0) {
        result.add(
          _Price(
            m.start,
            m.end,
            amount,
            RegExp(r'[OIlSB]', caseSensitive: false).hasMatch(
              raw.replaceFirst(RegExp(r'^rp\.?\s*', caseSensitive: false), ''),
            ),
            parsed.warnings.isNotEmpty,
          ),
        );
      }
    }
    return result;
  }

  TransactionDraft parse(List<OcrLine> input, ParserContext ctx) {
    final lines = mergeOcrLines(input);
    final warnings = <DraftWarning>[];
    void warn(String code, String message, [DraftField? field]) =>
        warnings.add(DraftWarning(code: code, message: message, field: field));
    final prices = [for (final line in lines) ..._prices(line.text)];
    if (prices.any((p) => p.corrected)) {
      warn(
        'OCR_CORRECTED',
        'Ada karakter angka yang diperbaiki. Periksa teks OCR dan jumlah.',
        DraftField.amount,
      );
    }
    if (prices.any((p) => p.ambiguous)) {
      warn(
        'AMBIGUOUS_SEPARATOR',
        'Pemisah angka kurang jelas. Periksa jumlah.',
        DraftField.amount,
      );
    }
    final totals = <(int, int, int)>[];
    var explicit = false;
    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].text;
      if (!_total.hasMatch(text) || _notTotal.hasMatch(text)) continue;
      final own = _prices(text);
      final next =
          i + 1 < lines.length &&
              !_nonItem.hasMatch(lines[i + 1].text) &&
              !_address.hasMatch(lines[i + 1].text) &&
              _date(lines[i + 1].text, ctx) == null
          ? _prices(lines[i + 1].text)
          : <_Price>[];
      final price = own.lastOrNull ?? next.lastOrNull;
      if (price != null) {
        final rank =
            RegExp(
              r'GRAND\s+TOTAL|TOTAL\s+BAYAR|NETTO',
              caseSensitive: false,
            ).hasMatch(text)
            ? 2
            : 1;
        totals.add((rank, i, price.amount));
      }
    }
    totals.sort((a, b) {
      final rank = b.$1.compareTo(a.$1);
      return rank == 0 ? b.$2.compareTo(a.$2) : rank;
    });
    int? amount = totals.firstOrNull?.$3;
    explicit = amount != null;
    if (amount == null) {
      final fallback = <int>[];
      final midpoint = lines.isEmpty
          ? 0
          : (lines.first.top + lines.last.bottom) / 2;
      for (final line in lines.where((l) => l.centerY >= midpoint)) {
        if (_date(line.text, ctx) != null) continue;
        if (RegExp(
          r'\b(TUNAI|CASH|KEMBALI|CHANGE|TOTAL\s+(ITEM|QTY)|TELP|NPWP)\b',
          caseSensitive: false,
        ).hasMatch(line.text)) {
          continue;
        }
        final price = _prices(line.text).lastOrNull;
        if (price != null && price.amount >= 1000) fallback.add(price.amount);
      }
      if (fallback.isNotEmpty) {
        amount = fallback.reduce((a, b) => a > b ? a : b);
      }
      warn(
        'TOTAL_FALLBACK',
        'Total tidak terbaca jelas. Periksa jumlah.',
        DraftField.amount,
      );
    }
    if (totals.map((t) => t.$3).toSet().length > 1) {
      warn(
        'MULTIPLE_TOTALS',
        'Ada beberapa total berbeda. Periksa jumlah.',
        DraftField.amount,
      );
    }
    final items = <DraftItem>[];
    var tax = 0, discount = 0;
    for (final line in lines) {
      final text = line.text;
      if (_date(text, ctx) != null) continue;
      final price = _prices(text).lastOrNull;
      if (price == null || text.substring(price.end).trim().isNotEmpty) {
        continue;
      }
      if (RegExp(
        r'\b(PPN|PAJAK|TAX|SERVICE)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        tax += price.amount;
        continue;
      }
      if (RegExp(
        r'\b(DISKON|DISCOUNT)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        discount += price.amount;
        continue;
      }
      if (_nonItem.hasMatch(text) || _address.hasMatch(text)) continue;
      final name = text.substring(0, price.start).trim();
      if (name.isEmpty || RegExp(r'\d[/\-]\d').hasMatch(name)) continue;
      if (!RegExp(r'[A-Za-z]').hasMatch(name) &&
          !RegExp(r'\d\s*[xX]\s*\d').hasMatch(name)) {
        continue;
      }
      // A bare quantity at the end is kept as useful receipt context.
      items.add(DraftItem(name: name, amount: price.amount));
    }
    if (amount != null && items.isNotEmpty) {
      final sum =
          items.fold<int>(0, (sum, item) => sum + item.amount) + tax - discount;
      if ((sum - amount).abs() * 100 > amount) {
        warn(
          'TOTAL_MISMATCH',
          'Jumlah item, pajak, layanan, dan diskon berbeda lebih dari 1% dari total.',
          DraftField.amount,
        );
      }
    }
    final storeParts = <String>[];
    for (final line in lines) {
      if (storeParts.length == 3) break;
      final text = line.text.trim();
      if (_date(text, ctx) != null) continue;
      if (_total.hasMatch(text) ||
          items.any((item) => text.startsWith(item.name))) {
        break;
      }
      if (_address.hasMatch(text) ||
          _nonItem.hasMatch(text) ||
          RegExp(r'\d[/\-]\d|\d:\d').hasMatch(text)) {
        continue;
      }
      if (RegExp(r'[A-Za-z]{3}').hasMatch(text) && _prices(text).isEmpty) {
        storeParts.add(text);
      }
    }
    final store = storeParts.isEmpty ? 'Struk' : storeParts.join(' ');
    if (storeParts.isEmpty) warn('STORE_MISSING', 'Nama toko belum terbaca.');
    final raw = lines.map((l) => l.text).join('\n');
    final dateText = _numericDates(raw);
    if (dateText != raw) {
      warn(
        'DATE_OCR_CORRECTED',
        'Ada karakter tanggal atau jam yang diperbaiki. Periksa tanggal.',
        DraftField.occurredAt,
      );
    }
    final date = _date(raw, ctx);
    if (date == null) {
      warn(
        'DEFAULT_DATE',
        'Tanggal struk tidak terbaca. Menggunakan hari ini.',
        DraftField.occurredAt,
      );
    }
    final now = ctx.clock.now();
    final time = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').firstMatch(dateText);
    final base = date ?? now;
    final occurredAt = (now.isUtc ? DateTime.utc : DateTime.new)(
      base.year,
      base.month,
      base.day,
      time == null ? (date == null ? now.hour : 0) : int.parse(time.group(1)!),
      time == null
          ? (date == null ? now.minute : 0)
          : int.parse(time.group(2)!),
    ).toUtc();
    String? accountId;
    final methods =
        RegExp(
              r'\b(QRIS|DEBIT|TUNAI|CASH|GO\s*PAY|OVO|DANA)\b',
              caseSensitive: false,
            )
            .allMatches(raw)
            .map((m) => m.group(0)!.toLowerCase().replaceAll(' ', ''))
            .toSet();
    final matched = ctx.accounts
        .where(
          (a) => [a.name, ...a.aliases].any((name) {
            final normalized = name.toLowerCase().replaceAll(' ', '');
            return methods.contains(normalized) ||
                normalized == 'tunai' && methods.contains('cash');
          }),
        )
        .toList();
    if (matched.length == 1) {
      accountId = matched.single.id;
    } else {
      accountId = ctx.accounts
          .where((a) => a.id == ctx.lastAccountId)
          .firstOrNull
          ?.id;
      if (accountId != null) {
        warn(
          'DEFAULT_ACCOUNT',
          'Periksa akun pembayaran yang terakhir dipakai.',
          DraftField.accountId,
        );
      }
      if (matched.length > 1) {
        warn(
          'MULTIPLE_ACCOUNTS',
          'Metode pembayaran tidak tunggal. Pilih akun.',
          DraftField.accountId,
        );
      }
    }
    var keywords = store.toLowerCase();
    if (RegExp('indomaret|alfamart').hasMatch(keywords)) {
      keywords += ' belanja';
    } else if (RegExp('spbu|pertamina|shell').hasMatch(keywords)) {
      keywords += ' bensin';
    } else if (RegExp('apotek|kimia farma').hasMatch(keywords)) {
      keywords += ' obat';
    } else if (RegExp('pln').hasMatch(keywords)) {
      keywords += ' listrik';
    } else if (RegExp('cafe|café|kafe|kopi|coffee').hasMatch(keywords)) {
      keywords += ' kopi';
    } else if (RegExp('resto|bakery').hasMatch(keywords)) {
      keywords += ' makan';
    }
    final category = const CategoryMatcher().match(
      keywords,
      ctx,
      TransactionType.expense,
    );
    warnings.addAll(category.warnings);
    final confidence =
        (.3 +
                (explicit ? .3 : 0) +
                (items.isNotEmpty ? .1 : 0) +
                (date != null ? .1 : 0) +
                (matched.length == 1 ? .1 : 0) +
                (category.categoryId != null ? .1 : 0) -
                warnings.length * .1)
            .clamp(0.0, 1.0);
    return TransactionDraft(
      type: TransactionType.expense,
      source: DraftSource.receipt,
      amount: amount,
      accountId: accountId,
      categoryId: category.categoryId,
      occurredAt: occurredAt,
      confidence: confidence,
      rawText: raw,
      warnings: warnings,
      items: items,
      note: '$store - ${items.length} item',
    );
  }

  DateTime? _date(String raw, ParserContext ctx) {
    raw = _numericDates(raw);
    final patterns = <RegExp>[
      RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'),
      RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{4}|\d{2})\b'),
      RegExp(
        r'\b(\d{1,2})\s+(Jan(?:uari)?|Feb(?:ruari)?|Mar(?:et)?|Apr(?:il)?|Mei|Jun(?:i)?|Jul(?:i)?|Agu(?:stus)?|Sep(?:tember)?|Okt(?:ober)?|Nov(?:ember)?|Des(?:ember)?)\s+(\d{4})\b',
        caseSensitive: false,
      ),
    ];
    const months = [
      'jan',
      'feb',
      'mar',
      'apr',
      'mei',
      'jun',
      'jul',
      'agu',
      'sep',
      'okt',
      'nov',
      'des',
    ];
    for (var i = 0; i < patterns.length; i++) {
      for (final m in patterns[i].allMatches(raw)) {
        var year = int.parse(m.group(i == 0 ? 1 : 3)!);
        if (year < 100) year += year < 70 ? 2000 : 1900;
        final month = i == 2
            ? months.indexOf(m.group(2)!.toLowerCase().substring(0, 3)) + 1
            : int.parse(m.group(2)!);
        final day = int.parse(m.group(i == 0 ? 3 : 1)!);
        final date = DateTime.utc(year, month, day);
        if (date.year == year && date.month == month && date.day == day) {
          return date;
        }
      }
    }
    return null;
  }
}
