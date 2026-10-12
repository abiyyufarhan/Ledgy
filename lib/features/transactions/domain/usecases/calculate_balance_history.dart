/// A signed balance change, including an account's initial balance.
class BalanceChange {
  const BalanceChange({required this.occurredAt, required this.amount});

  final DateTime occurredAt;
  final int amount;
}

class DailyBalance {
  const DailyBalance(this.date, this.balance);

  final DateTime date;
  final int balance;
}

class BalanceHistoryCalculator {
  const BalanceHistoryCalculator._();

  /// Calendar dates are local; stored timestamps can be UTC. Earlier changes
  /// form the opening balance rather than being discarded at the month boundary.
  static List<DailyBalance> currentMonth({
    required DateTime now,
    required Iterable<BalanceChange> changes,
  }) {
    final local = now.toLocal();
    return calculate(
      startDate: DateTime(local.year, local.month),
      endDate: DateTime(local.year, local.month, local.day),
      changes: changes,
    );
  }

  static List<DailyBalance> calculate({
    required DateTime startDate,
    required DateTime endDate,
    required Iterable<BalanceChange> changes,
  }) {
    final localStart = startDate.toLocal();
    final localEnd = endDate.toLocal();
    final start = DateTime(localStart.year, localStart.month, localStart.day);
    final end = DateTime(localEnd.year, localEnd.month, localEnd.day);
    if (end.isBefore(start)) {
      throw ArgumentError('endDate must not precede startDate');
    }
    final dailyChanges = <DateTime, int>{};
    var balance = 0;
    for (final change in changes) {
      final local = change.occurredAt.toLocal();
      var day = DateTime(local.year, local.month, local.day);
      if (day.isBefore(start)) {
        balance += change.amount;
        continue;
      }
      // Match the current ledger total, which includes already-recorded
      // future-dated entries. Do not draw a forecast into the rest of the month.
      if (day.isAfter(end)) day = end;
      dailyChanges[day] = (dailyChanges[day] ?? 0) + change.amount;
    }

    final points = <DailyBalance>[];
    // Construct calendar dates instead of adding 24 hours across DST changes.
    for (
      var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      balance += dailyChanges[day] ?? 0;
      points.add(DailyBalance(day, balance));
    }
    return points;
  }
}
