import 'package:intl/intl.dart';

final _rupiahFormatter = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

String formatRupiah(int amount) => _rupiahFormatter.format(amount);

String formatShortDate(DateTime value) =>
    DateFormat('d MMM', 'id_ID').format(value.toLocal());

/// Compact transaction timestamp in 24-hour Indonesian format.
String formatTransactionDateTime(DateTime value) =>
    DateFormat('d MMM • HH.mm', 'id_ID').format(value.toLocal());
