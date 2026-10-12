import '../transaction_draft.dart';
import 'parse_span.dart';
import 'parser_context.dart';

final class DateParseResult {
  const DateParseResult(this.occurredAt, this.spans, this.warnings);
  final DateTime? occurredAt;
  final List<ParseSpan> spans;
  final List<DraftWarning> warnings;
}

final class _DateCandidate {
  const _DateCandidate(this.date, this.span);
  final DateTime? date;
  final ParseSpan span;
}

final class DateParser {
  const DateParser();
  static const _days = {
    'senin': 1,
    'selasa': 2,
    'rabu': 3,
    'kamis': 4,
    'jumat': 5,
    'sabtu': 6,
    'minggu': 7,
  };
  static const _months = {
    'januari': 1,
    'jan': 1,
    'februari': 2,
    'feb': 2,
    'maret': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'mei': 5,
    'juni': 6,
    'jun': 6,
    'juli': 7,
    'jul': 7,
    'agustus': 8,
    'agu': 8,
    'september': 9,
    'sep': 9,
    'oktober': 10,
    'okt': 10,
    'november': 11,
    'nov': 11,
    'desember': 12,
    'des': 12,
  };

  DateParseResult parse(String text, Clock clock) {
    final now = clock.now();
    DateTime at(int year, int month, int day, [int? hour]) => now.isUtc
        ? DateTime.utc(
            year,
            month,
            day,
            hour ?? now.hour,
            hour == null ? now.minute : 0,
          )
        : DateTime(
            year,
            month,
            day,
            hour ?? now.hour,
            hour == null ? now.minute : 0,
          );
    final candidates = <_DateCandidate>[];
    void add(RegExp regex, DateTime? Function(RegExpMatch) date) {
      for (final match in regex.allMatches(text)) {
        final span = ParseSpan(match.start, match.end);
        if (!candidates.any((c) => c.span.overlaps(span))) {
          candidates.add(_DateCandidate(date(match), span));
        }
      }
    }

    add(
      RegExp(
        r'\b(?:kemarin lusa|hari ini|kemarin|minggu lalu|tadi (?:pagi|siang|sore|malam))\b',
      ),
      (m) {
        final value = m.group(0)!;
        final offset = switch (value) {
          'kemarin lusa' => -2,
          'kemarin' => -1,
          'minggu lalu' => -7,
          _ => 0,
        };
        final hour = switch (value) {
          'tadi pagi' => 7,
          'tadi siang' => 12,
          'tadi sore' => 16,
          'tadi malam' => 20,
          _ => null,
        };
        return at(now.year, now.month, now.day + offset, hour);
      },
    );
    add(
      RegExp(
        r'\b(?:hari )?(senin|selasa|rabu|kamis|jumat|sabtu|minggu)( lalu)?\b',
      ),
      (m) {
        final day = _days[m.group(1)!]!;
        return at(
          now.year,
          now.month,
          now.day - now.weekday + day - (m.group(2) == null ? 0 : 7),
        );
      },
    );
    DateTime? checked(int year, int month, int day) {
      if (year < 1 ||
          year > 9999 ||
          month < 1 ||
          month > 12 ||
          day < 1 ||
          day > 31) {
        return null;
      }
      final date = at(year, month, day);
      return date.year == year && date.month == month && date.day == day
          ? date
          : null;
    }

    add(
      RegExp(
        '\\b(?:tanggal )?(\\d{1,2}) (${_months.keys.join('|')})(?: (\\d{4}))?\\b',
      ),
      (m) => checked(
        int.tryParse(m.group(3) ?? '') ?? now.year,
        _months[m.group(2)!]!,
        int.parse(m.group(1)!),
      ),
    );
    add(
      RegExp(r'\b(?:tanggal )?(\d{1,2})/(\d{1,2})(?:/(\d{4}))?\b'),
      (m) => checked(
        int.tryParse(m.group(3) ?? '') ?? now.year,
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      ),
    );
    add(
      RegExp(r'\btanggal (\d{1,2})\b'),
      (m) => checked(now.year, now.month, int.parse(m.group(1)!)),
    );
    candidates.sort((a, b) => a.span.start.compareTo(b.span.start));
    final warnings = <DraftWarning>[];
    if (candidates.any((c) => c.date == null)) {
      warnings.add(
        const DraftWarning(
          code: 'INVALID_DATE',
          field: DraftField.occurredAt,
          message: 'Tanggal tidak valid. Pilih tanggal yang benar.',
        ),
      );
    }
    if (candidates.length > 1) {
      warnings.add(
        const DraftWarning(
          code: 'MULTIPLE_DATES',
          field: DraftField.occurredAt,
          message: 'Ada beberapa tanggal. Tanggal pertama dipilih.',
        ),
      );
    }
    return DateParseResult(
      candidates.isEmpty
          ? at(now.year, now.month, now.day).toUtc()
          : candidates.first.date?.toUtc(),
      List.unmodifiable(candidates.map((c) => c.span)),
      List.unmodifiable(warnings),
    );
  }
}
