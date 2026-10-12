import '../transaction_draft.dart';
import 'normalizer.dart';
import 'parse_span.dart';

final class AmountCandidate {
  const AmountCandidate(this.amount, this.span, this.explicit, this.warnings);
  final int amount;
  final ParseSpan span;
  final bool explicit;
  final List<DraftWarning> warnings;
}

final class AmountParseResult {
  const AmountParseResult({
    this.amount,
    required this.spans,
    required this.warnings,
    required this.clear,
  });
  final int? amount;
  final List<ParseSpan> spans;
  final List<DraftWarning> warnings;
  final bool clear;
}

final class _Token {
  const _Token(this.text, this.start, this.end);
  final String text;
  final int start, end;
}

final class _Part {
  const _Part(this.value, this.next, this.factor, this.warnings);
  final BigInt value;
  final int next, factor;
  final List<DraftWarning> warnings;
}

final class AmountParser {
  const AmountParser();
  static final _max = BigInt.parse('9223372036854775807');
  static const _units = {
    'rb': 1000,
    'ribu': 1000,
    'k': 1000,
    'jt': 1000000,
    'juta': 1000000,
  };
  static const _digits = {
    'nol': 0,
    'satu': 1,
    'dua': 2,
    'tiga': 3,
    'empat': 4,
    'lima': 5,
    'enam': 6,
    'tujuh': 7,
    'delapan': 8,
    'sembilan': 9,
  };

  AmountParseResult parse(String text, {List<ParseSpan> excluded = const []}) {
    final tokens = RegExp(r'\d+(?:[.,]\d+)*|[a-z]+|¤|[^\s]')
        .allMatches(text)
        .map((m) => _Token(m.group(0)!, m.start, m.end))
        .toList();
    final candidates = <AmountCandidate>[];
    final rejected = <DraftWarning>[];
    for (var i = 0; i < tokens.length;) {
      final first = tokens[i];
      if (excluded.any(
        (span) => span.overlaps(ParseSpan(first.start, first.end)),
      )) {
        i++;
        continue;
      }
      final marker = first.text == Normalizer.moneyToken;
      final start = marker ? i + 1 : i;
      if (start >= tokens.length) {
        i++;
        continue;
      }
      // Digits embedded in account names/identifiers are not bare money.
      if (!marker &&
          first.start > 0 &&
          RegExp(r'[a-z0-9]').hasMatch(text[first.start - 1])) {
        i++;
        continue;
      }
      final part = _part(tokens, start);
      if (part == null) {
        i++;
        continue;
      }
      var value = part.value;
      var end = part.next;
      var factor = part.factor;
      var explicit = marker || factor > 1;
      final warnings = [...part.warnings];
      while (factor > 1 && end < tokens.length) {
        final next = _part(tokens, end);
        if (next == null ||
            next.factor <= 1 ||
            next.factor >= factor ||
            text
                .substring(tokens[end - 1].end, tokens[end].start)
                .trim()
                .isNotEmpty) {
          break;
        }
        value += next.value;
        warnings.addAll(next.warnings);
        factor = next.factor;
        end = next.next;
      }
      if (end < tokens.length && tokens[end].text == Normalizer.moneyToken) {
        explicit = true;
        end++;
      }
      final span = ParseSpan(first.start, tokens[end - 1].end);
      if (excluded.any((other) => span.overlaps(other))) {
        i = end;
        continue;
      }
      final nextText = end < tokens.length ? tokens[end].text : '';
      final identifierContext = RegExp(
        r'\b(?:tahun|nomor|rekening|telepon|telp|no)\s*$',
      ).hasMatch(text.substring(0, first.start));
      final countContext =
          containsPhrase(
            'porsi orang buah kali lembar nomor no tahun',
            nextText,
          ) &&
          nextText.isNotEmpty;
      final embeddedSuffix =
          end < tokens.length &&
          tokens[end].start == tokens[end - 1].end &&
          RegExp(r'^[a-z]+$').hasMatch(nextText);
      if ((!explicit &&
          (value < BigInt.from(1000) ||
              countContext ||
              identifierContext ||
              embeddedSuffix))) {
        rejected.addAll(warnings);
        i = end;
        continue;
      }
      if (first.start > 0 && text[first.start - 1] == '-') {
        rejected.add(
          const DraftWarning(
            code: 'NEGATIVE_AMOUNT',
            field: DraftField.amount,
            message: 'Jumlah negatif tidak dapat dipakai. Isi jumlah positif.',
          ),
        );
        i = end;
        continue;
      }
      if (value < BigInt.zero || value > _max) {
        rejected.addAll(warnings);
        if (!warnings.any((w) => w.code == 'FRACTIONAL_RUPIAH')) {
          rejected.add(
            const DraftWarning(
              code: 'AMOUNT_OVERFLOW',
              field: DraftField.amount,
              message: 'Jumlah terlalu besar untuk disimpan.',
            ),
          );
        }
      } else {
        candidates.add(
          AmountCandidate(
            value.toInt(),
            span,
            explicit,
            List.unmodifiable(warnings),
          ),
        );
      }
      i = end;
    }
    if (candidates.isEmpty) {
      return AmountParseResult(
        amount: null,
        spans: const [],
        clear: false,
        warnings: [
          ...rejected,
          const DraftWarning(
            code: 'NO_AMOUNT',
            field: DraftField.amount,
            message: 'Jumlah uang belum terbaca.',
          ),
        ],
      );
    }
    final preferred = candidates.where((c) => c.explicit).toList();
    final pool = preferred.isEmpty ? candidates : preferred;
    final chosen = pool.first;
    final warnings = [...rejected, ...chosen.warnings];
    if (pool.length > 1) {
      warnings.add(
        const DraftWarning(
          code: 'MULTIPLE_AMOUNTS',
          field: DraftField.amount,
          message:
              'Ada beberapa jumlah. Jumlah pertama dipilih; periksa kembali.',
        ),
      );
    }
    return AmountParseResult(
      amount: chosen.amount,
      spans: candidates.map((c) => c.span).toList(),
      warnings: List.unmodifiable(warnings),
      clear: warnings.isEmpty,
    );
  }

  _Part? _part(List<_Token> tokens, int start) {
    if (start >= tokens.length) return null;
    final token = tokens[start].text;
    if (token == 'sejuta' || token == 'seribu') {
      final factor = token == 'sejuta' ? 1000000 : 1000;
      return _Part(BigInt.from(factor), start + 1, factor, const []);
    }
    if (token == 'setengah' &&
        start + 1 < tokens.length &&
        _units.containsKey(tokens[start + 1].text)) {
      final factor = _units[tokens[start + 1].text]!;
      return _Part(BigInt.from(factor ~/ 2), start + 2, factor, const []);
    }
    final numeric = RegExp(r'^\d').hasMatch(token);
    var end = start + 1;
    BigInt? numerator;
    var denominator = BigInt.one;
    final warnings = <DraftWarning>[];
    if (numeric) {
      final unit = end < tokens.length ? _units[tokens[end].text] : null;
      final separators = RegExp(r'[.,]').allMatches(token).toList();
      if (separators.isEmpty) {
        numerator = BigInt.tryParse(token);
      } else if (unit == null &&
          RegExp(
            r'^(?:\d{1,3}(?:\.\d{3})+|\d{4,}),00$|^\d{1,3}(?:,\d{3})+\.00$',
          ).hasMatch(token)) {
        // Whole rupiah formatted with zero cents, without changing source spans.
        numerator = BigInt.tryParse(
          token.substring(0, token.length - 3).replaceAll(RegExp(r'[.,]'), ''),
        );
      } else if (unit != null && separators.length == 1) {
        final parts = token.split(RegExp(r'[.,]'));
        numerator = BigInt.tryParse(parts.join());
        denominator = BigInt.from(10).pow(parts.last.length);
        if (parts.last.length == 3) warnings.add(_ambiguousSeparator);
      } else if (RegExp(r'^\d{1,3}([.,])\d{3}(?:\1\d{3})*$').hasMatch(token)) {
        numerator = BigInt.tryParse(token.replaceAll(RegExp(r'[.,]'), ''));
        if (unit != null) warnings.add(_ambiguousSeparator);
      } else {
        // A malformed grouping is preserved as an uncertain candidate, never rounded.
        numerator = BigInt.tryParse(token.replaceAll(RegExp(r'[.,]'), ''));
        warnings.add(_ambiguousSeparator);
      }
    } else {
      final words = _wordNumber(tokens, start);
      if (words == null) return null;
      numerator = BigInt.from(words.$1);
      end = words.$2;
    }
    if (numerator == null) return null;
    final factor = end < tokens.length ? _units[tokens[end].text] ?? 1 : 1;
    if (factor > 1) end++;
    final scaled = numerator * BigInt.from(factor);
    if (scaled.remainder(denominator) != BigInt.zero) {
      // No fractional rupiah: flag and leave the amount unresolved.
      return _Part(_max + BigInt.one, end, factor, [
        ...warnings,
        const DraftWarning(
          code: 'FRACTIONAL_RUPIAH',
          field: DraftField.amount,
          message: 'Pecahan rupiah tidak dapat dipakai; isi jumlah utuh.',
        ),
      ]);
    }
    return _Part(scaled ~/ denominator, end, factor, warnings);
  }

  static const _ambiguousSeparator = DraftWarning(
    code: 'AMBIGUOUS_SEPARATOR',
    field: DraftField.amount,
    message: 'Pemisah angka ambigu. Periksa jumlah yang dipilih.',
  );

  (int, int)? _wordNumber(List<_Token> tokens, int i) {
    var total = 0;
    if (tokens[i].text == 'seratus') {
      total = 100;
      i++;
    } else if (_digits.containsKey(tokens[i].text) &&
        i + 1 < tokens.length &&
        tokens[i + 1].text == 'ratus') {
      total = _digits[tokens[i].text]! * 100;
      i += 2;
    }
    if (i >= tokens.length) return total == 0 ? null : (total, i);
    final token = tokens[i].text;
    if (token == 'sepuluh' || token == 'sebelas') {
      return (total + (token == 'sepuluh' ? 10 : 11), i + 1);
    }
    final digit = _digits[token];
    if (digit == null) return total == 0 ? null : (total, i);
    i++;
    if (i < tokens.length && tokens[i].text == 'belas') {
      return (total + 10 + digit, i + 1);
    }
    if (i < tokens.length && tokens[i].text == 'puluh') {
      total += digit * 10;
      i++;
      if (i < tokens.length && _digits.containsKey(tokens[i].text)) {
        total += _digits[tokens[i].text]!;
        i++;
      }
      return (total, i);
    }
    return (total + digit, i);
  }
}
