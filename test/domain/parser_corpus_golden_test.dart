import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/quick_input/domain/parser/parser_pipeline.dart';
import 'package:ledgy/features/quick_input/domain/receipt/ocr_line.dart';
import 'package:ledgy/features/quick_input/domain/receipt/receipt_parser.dart';

import '../support/parser_corpus.dart';

void main() {
  test('golden corpus: akurasi setiap kolom dan waktu parser', () async {
    final rows = readCorpusCsv(
      File('test/fixtures/phrases.csv').readAsStringSync(),
    );
    expect(rows.removeAt(0), [
      'kalimat',
      'jenis',
      'jumlah',
      'kategori',
      'akun',
      'tanggal',
    ]);
    expect(rows.length, greaterThanOrEqualTo(100));
    final ctx = corpusContext();
    const pipeline = ParserPipeline();
    final hits = <String, int>{
      for (final key in ['jenis', 'jumlah', 'kategori', 'akun', 'tanggal'])
        key: 0,
    };
    final failures = <Map<String, Object?>>[];
    final times = <int>[];
    for (var i = 0; i < 20; i++) {
      await pipeline.parse(rows[i][0], ctx);
    }
    var moneyCases = 0, moneyHits = 0;
    for (final row in rows) {
      expect(row.length, 6, reason: row.first);
      final timer = Stopwatch()..start();
      final drafts = await pipeline.parse(row[0], ctx);
      timer.stop();
      times.add(timer.elapsedMicroseconds);
      expect(drafts.length, 1, reason: row[0]);
      final d = drafts.single;
      final actual = [
        d.type.name,
        d.amount?.toString() ?? '',
        d.categoryId ?? '',
        d.accountId ?? '',
        d.occurredAt?.toIso8601String().substring(0, 10) ?? '',
      ];
      for (var i = 0; i < actual.length; i++) {
        final key = hits.keys.elementAt(i);
        if (actual[i] == row[i + 1]) {
          hits[key] = hits[key]! + 1;
        } else {
          failures.add({
            'kalimat': row[0],
            'kolom': key,
            'expected': row[i + 1],
            'actual': actual[i],
          });
        }
      }
      if (row[2].isNotEmpty) {
        moneyCases++;
        if (actual[1] == row[2]) moneyHits++;
      }
    }
    times.sort();
    final histogram = <String, int>{};
    for (final failure in failures) {
      final key = failure['kolom']! as String;
      histogram[key] = (histogram[key] ?? 0) + 1;
    }
    final report = <String, Object?>{
      'provenance': 'synthetic everyday phrases; not personal usage logs',
      'clock': '2026-10-08T10:00:00Z',
      'cases': rows.length,
      'accuracyPercent': {
        for (final key in hits.keys) key: hits[key]! * 100 / rows.length,
      },
      'positiveAmountAccuracyPercent': moneyHits * 100 / moneyCases,
      'parserMicroseconds': {
        'p50': times[times.length ~/ 2],
        'p95': times[((times.length - 1) * .95).ceil()],
        'max': times.last,
      },
      'failureCounts': histogram,
      'failures': failures,
    };
    Directory('build').createSync();
    File('build/parser-corpus-report.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(report));
    expect(moneyHits / moneyCases, greaterThanOrEqualTo(.9));
    expect(hits['jumlah']! / rows.length, greaterThanOrEqualTo(.9));
    expect(times[((times.length - 1) * .95).ceil()], lessThan(50000));
  });

  test('golden struk: total benar minimal 80% dari fixture sintetis', () {
    const expected = {
      'minimarket': 30000,
      'restoran': 52200,
      'spbu': 50000,
      'apotek': 40000,
      'diskon_panjang': 120000,
      'total_terpotong': 35000,
      'buram': 35000,
      'miring': 30000,
    };
    final results = <String, Object?>{};
    var hits = 0;
    for (final entry in expected.entries) {
      final raw = jsonDecode(
        File('test/fixtures/receipts/${entry.key}.json').readAsStringSync(),
      ) as List;
      final lines = raw
          .map((l) => OcrLine.fromJson(Map<String, dynamic>.from(l as Map)))
          .toList();
      final d = const ReceiptParser().parse(lines, corpusContext());
      if (d.amount == entry.value) hits++;
      results[entry.key] = {'expected': entry.value, 'actual': d.amount};
    }
    final report = {
      'provenance': 'synthetic OCR JSON; excludes real device OCR',
      'accuracyPercent': hits * 100 / expected.length,
      'cases': results,
    };
    Directory('build').createSync();
    File('build/receipt-corpus-report.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print(jsonEncode(report));
    expect(hits / expected.length, greaterThanOrEqualTo(.8));
  });

  test('CSV mempertahankan koma desimal dan kutip', () {
    expect(readCorpusCsv('"a, b","kata ""kopi"""\n'), [
      ['a, b', 'kata "kopi"'],
    ]);
  });
}
