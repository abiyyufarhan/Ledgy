import 'package:intl/intl.dart';

enum TransactionPeriod {
  daily('Harian', 'Hari'),
  monthly('Bulanan', 'Bulan'),
  yearly('Tahunan', 'Tahun');

  const TransactionPeriod(this.label, this.unit);
  final String label;
  final String unit;

  bool contains(DateTime value, DateTime selected) {
    final local = value.toLocal();
    final date = selected.toLocal();
    if (local.year != date.year) return false;
    return switch (this) {
      daily => local.month == date.month && local.day == date.day,
      monthly => local.month == date.month,
      yearly => true,
    };
  }

  DateTime shift(DateTime date, int offset) {
    if (this == daily) {
      return DateTime(date.year, date.month, date.day + offset);
    }
    final target = this == monthly
        ? DateTime(date.year, date.month + offset)
        : DateTime(date.year + offset, date.month);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month, date.day.clamp(1, lastDay));
  }

  String title(DateTime date) => DateFormat(switch (this) {
    daily => 'd MMMM yyyy',
    monthly => 'MMMM yyyy',
    yearly => 'yyyy',
  }, 'id_ID').format(date);

  String fileDate(DateTime date) => DateFormat(switch (this) {
    daily => 'yyyy-MM-dd',
    monthly => 'yyyy-MM',
    yearly => 'yyyy',
  }).format(date);
}
