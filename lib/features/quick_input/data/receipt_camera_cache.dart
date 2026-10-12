import 'dart:io';

import 'package:path/path.dart' as p;

/// image_picker's Android camera creates a UUID-prefixed JPG in app cache.
/// Snapshot ownership lets us remove even a cancelled camera's unreturned file,
/// while preserving files present before this scan and all gallery originals.
Future<Set<String>> cameraCacheFiles(Directory cache) async {
  final files = <String>{};
  final pattern = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}[^/\\]*\.jpg$',
    caseSensitive: false,
  );
  await for (final entry in cache.list(followLinks: false)) {
    if (entry is File && pattern.hasMatch(p.basename(entry.path))) {
      files.add(entry.path);
    }
  }
  return files;
}

Future<void> clearCameraCache(
  Directory cache, {
  Set<String> preserve = const {},
}) async {
  for (final path in (await cameraCacheFiles(cache)).difference(preserve)) {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
