/// RFC 4180-compatible CSV reader/writer: commas, quotes, and embedded newlines.
/// The interchange format uses integer rupiah and ISO-8601 UTC timestamps.
abstract final class LedgerCsv {
  /// Reject calendar overflows that DateTime.tryParse silently normalizes.
  static DateTime? parseDate(String text) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        int.parse(match[4]!) > 23 ||
        int.parse(match[5]!) > 59 ||
        int.parse(match[6] ?? '0') > 59) {
      return null;
    }
    final zone = match[7]!;
    if (zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 23 ||
            int.parse(zone.substring(4)) > 59)) {
      return null;
    }
    return DateTime.tryParse(text);
  }

  static const headers = [
    'id',
    'type',
    'amount',
    'account_id',
    'account_name',
    'to_account_id',
    'to_account_name',
    'category_id',
    'category_name',
    'note',
    'occurred_at',
  ];
  static const exportHeaders = [
    ...headers,
    'recipient_name',
    'recipient_account',
  ];

  static String encode(List<List<String>> rows) {
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
    return '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';
  }

  /// Prevent formulas being executed when the export is opened in Excel.
  static String safeText(String value) =>
      RegExp(r'^[=+@\-\t\r]').hasMatch(value) ? "'$value" : value;
  static String originalText(String value) =>
      value.startsWith("'") &&
          value.length > 1 &&
          RegExp(r'^[=+@\-\t\r]').hasMatch(value.substring(1))
      ? value.substring(1)
      : value;

  static List<Map<String, String>> decode(String input) {
    final text = input.replaceFirst(RegExp(r'^\uFEFF'), '');
    final separator = text.split(RegExp(r'[\r\n]')).first.contains(',')
        ? ','
        : ';';
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    var closedQuote = false;
    void finishCell() {
      row.add(cell.toString());
      cell = StringBuffer();
      closedQuote = false;
    }

    void finishRow() {
      finishCell();
      if (row.any((value) => value.isNotEmpty)) rows.add(row);
      row = [];
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
            closedQuote = true;
          }
        } else {
          cell.write(char);
        }
      } else if (char == ',' || char == ';') {
        // The separator is fixed by the header; semicolons in comma CSV remain text.
        if (char == separator) {
          finishCell();
        } else {
          if (closedQuote) throw const FormatException('CSV tidak valid.');
          cell.write(char);
        }
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        finishRow();
      } else if (char == '"') {
        if (cell.isNotEmpty || closedQuote) {
          throw const FormatException('Tanda kutip CSV tidak valid.');
        }
        quoted = true;
      } else {
        if (closedQuote) {
          throw const FormatException('Ada teks setelah penutup kutip.');
        }
        cell.write(char);
      }
    }
    if (quoted) throw const FormatException('Tanda kutip CSV belum ditutup.');
    if (cell.isNotEmpty || row.isNotEmpty || closedQuote) finishRow();
    if (rows.isEmpty) throw const FormatException('CSV kosong.');
    final header = rows.removeAt(0).map((value) => value.trim()).toList();
    if (header.toSet().length != header.length ||
        !['type', 'amount', 'occurred_at'].every(header.contains)) {
      throw const FormatException('Header wajib: type, amount, occurred_at.');
    }
    return [
      for (final row in rows)
        if (row.length != header.length)
          throw const FormatException('Jumlah kolom CSV tidak sesuai header.')
        else
          Map.fromIterables(header, row),
    ];
  }

  static String fingerprint({
    required String type,
    required int amount,
    required String accountId,
    String? toAccountId,
    String? recipientName,
    String? recipientAccount,
    String? categoryId,
    String? note,
    required DateTime date,
  }) => encode([
    [
      type,
      '$amount',
      accountId,
      toAccountId ?? '',
      recipientName ?? '',
      recipientAccount ?? '',
      categoryId ?? '',
      (note ?? '').trim(),
      '${date.toUtc().millisecondsSinceEpoch ~/ 1000}',
    ],
  ]);
}
