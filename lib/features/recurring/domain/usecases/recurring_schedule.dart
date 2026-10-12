class DueOccurrences {
  const DueOccurrences(this.dates, this.next);
  final List<DateTime> dates;
  final DateTime next;
}

/// Calendar arithmetic in the supplied time zone. The original day is retained
/// so Jan 31 -> Feb 28 -> Mar 31, rather than permanently shifting to day 28.
abstract final class RecurringSchedule {
  static DueOccurrences due({
    required DateTime next,
    required DateTime now,
    required String frequency,
    required int interval,
    int? anchorDay,
    int batchSize = 500,
  }) {
    if (interval < 1 || batchSize < 1) {
      throw ArgumentError('Interval dan ukuran batch harus positif.');
    }
    if (!const ['daily', 'weekly', 'monthly'].contains(frequency)) {
      throw ArgumentError('Frekuensi tidak dikenali.');
    }
    final day = anchorDay ?? next.day;
    final dates = <DateTime>[];
    var cursor = next;
    while (!cursor.isAfter(now) && dates.length < batchSize) {
      dates.add(cursor);
      cursor = advance(cursor, frequency, interval, day);
    }
    return DueOccurrences(dates, cursor);
  }

  static DateTime advance(
    DateTime date,
    String frequency,
    int interval,
    int anchorDay,
  ) {
    DateTime calendar(int year, int month, int day) => date.isUtc
        ? DateTime.utc(year, month, day, date.hour, date.minute, date.second)
        : DateTime(year, month, day, date.hour, date.minute, date.second);
    if (frequency == 'daily' || frequency == 'weekly') {
      return calendar(
        date.year,
        date.month,
        date.day + interval * (frequency == 'weekly' ? 7 : 1),
      );
    }
    final target = calendar(date.year, date.month + interval, 1);
    final last = calendar(target.year, target.month + 1, 0).day;
    return calendar(target.year, target.month, anchorDay.clamp(1, last));
  }
}
