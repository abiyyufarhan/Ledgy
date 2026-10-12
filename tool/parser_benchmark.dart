import 'dart:convert';
import 'dart:io';

import 'package:ledgy/features/quick_input/domain/parser/parser_pipeline.dart';

import '../test/support/parser_corpus.dart';

/// Run separately from Flutter test workers to reduce scheduler interference.
Future<void> main() async {
  final rows = readCorpusCsv(
    File('test/fixtures/phrases.csv').readAsStringSync(),
  )..removeAt(0);
  final ctx = corpusContext();
  const parser = ParserPipeline();
  for (var i = 0; i < 5; i++) {
    for (final row in rows) {
      await parser.parse(row.first, ctx);
    }
  }
  final samples = <int>[];
  final slow = <Map<String, Object>>[];
  for (var i = 0; i < 5; i++) {
    for (final row in rows) {
      final timer = Stopwatch()..start();
      await parser.parse(row.first, ctx);
      timer.stop();
      samples.add(timer.elapsedMicroseconds);
      if (timer.elapsedMicroseconds >= 50000) {
        slow.add({
          'kalimat': row.first,
          'microseconds': timer.elapsedMicroseconds,
        });
      }
    }
  }
  samples.sort();
  final report = {
    'environment': '${Platform.operatingSystem}; Dart ${Platform.version}',
    'provenance': '120 synthetic phrases; desktop Dart VM; no real Android OCR',
    'warmupPasses': 5,
    'measuredPasses': 5,
    'samples': samples.length,
    'microseconds': {
      'p50': samples[samples.length ~/ 2],
      'p95': samples[((samples.length - 1) * .95).ceil()],
      'max': samples.last,
    },
    'budgetMicroseconds': 50000,
    'budgetMet': slow.isEmpty,
    'overBudget': slow,
  };
  Directory('build').createSync();
  final json = const JsonEncoder.withIndent('  ').convert(report);
  File('build/parser-benchmark-report.json').writeAsStringSync(json);
  stdout.writeln(json);
  if (slow.isNotEmpty) exitCode = 1;
}
