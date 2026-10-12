/// Pure integer comparisons keep currency amounts exact.
abstract final class BudgetAlertPolicy {
  static int? nextThreshold({
    required int budgeted,
    required int spent,
    Set<int> sent = const {},
  }) {
    if (budgeted <= 0 || spent < 0) return null;
    if (spent >= budgeted && !sent.contains(100)) return 100;
    if (spent * 100 >= budgeted * 80 &&
        !sent.contains(80) &&
        !sent.contains(100)) {
      return 80;
    }
    return null;
  }
}
