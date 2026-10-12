import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../local/data/local_finance_repository.dart';

/// Preferences and attachment links are device-only local_state entries.
/// No attachment path, image or OCR text enters the sync tables.
class ReceiptStorage {
  ReceiptStorage(this.finance, {this.directory});
  final LocalFinanceRepository finance;
  final Future<Directory> Function()? directory;
  Future<Directory> _directory() async => directory != null
      ? directory!()
      : Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'ledgy_2_0',
            'receipts',
          ),
        ).create(recursive: true);
  Future<bool> enabled() async =>
      await finance.state('receipt:save_photo') == 'true';
  Future<void> setEnabled(bool value) =>
      finance.setState('receipt:save_photo', '$value');
  Future<String> stage(String source) async {
    final target = p.join(
      (await _directory()).path,
      '${const Uuid().v4()}.jpg',
    );
    try {
      await File(source).copy(target);
      return target;
    } catch (_) {
      await remove(target);
      rethrow;
    }
  }

  Future<void> link(String transactionId, String path) =>
      finance.setState('receipt:attachment:$transactionId', p.basename(path));
  Future<String?> photoFor(String transactionId) async {
    final filename = await finance.state('receipt:attachment:$transactionId');
    if (filename == null ||
        !RegExp(r'^[0-9a-f-]{36}\.jpg$').hasMatch(filename)) {
      return null;
    }
    final path = p.join((await _directory()).path, filename);
    return await File(path).exists() ? path : null;
  }

  Future<void> remove(String path) async {
    final root = p.normalize((await _directory()).path);
    if (!p.isWithin(root, p.normalize(path))) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> clearAttachments() async {
    final rows = await finance.db
        .customSelect(
          "SELECT value FROM ledgy_local_state WHERE key LIKE 'receipt:attachment:%'",
        )
        .get();
    if (rows.isEmpty) return;
    final root = await _directory();
    for (final row in rows) {
      final name = row.read<String>('value');
      if (RegExp(r'^[0-9a-f-]{36}\.jpg$').hasMatch(name)) {
        await remove(p.join(root.path, name));
      }
    }
    await finance.db.customStatement(
      "DELETE FROM ledgy_local_state WHERE key LIKE 'receipt:attachment:%'",
    );
  }
}
