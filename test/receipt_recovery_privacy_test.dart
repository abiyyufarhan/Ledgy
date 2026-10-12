import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ledgy/features/quick_input/data/receipt_camera_cache.dart';
import 'package:ledgy/features/quick_input/domain/receipt/receipt_recovery.dart';
import 'package:ledgy/features/quick_input/domain/receipt/receipt_scan_backend.dart';
import 'package:ledgy/features/quick_input/domain/receipt/ocr_line.dart';

class RecoveryBackend implements ReceiptScanBackend {
  int attempts = 0;
  bool fail = false;
  @override
  Future<ReceiptPhoto?> recover() async {
    attempts++;
    if (fail) {
      throw const FileSystemException('test recovery failure');
    }
    return ReceiptPhoto('/private/recovered.jpg', Uint8List(1));
  }

  @override
  Future<ReceiptPhoto?> pick(ReceiptImageSource source) async => null;
  @override
  Future<List<OcrLine>> recognize(ReceiptPhoto photo) async => [];
  @override
  Future<void> remove(ReceiptPhoto photo) async {}
}

void main() {
  test(
    'returning to Dashboard never replays an already consumed recovered photo',
    () async {
      final backend = RecoveryBackend();
      final recovery = ReceiptRecovery(backend);
      final photo = await recovery.recoverOnce();
      expect(photo, isNotNull);
      await backend.remove(photo!);
      expect(await recovery.recoverOnce(), isNull);
      expect(backend.attempts, 1);
    },
  );
  test('failed recovery is not repeated on every Dashboard rebuild', () async {
    final backend = RecoveryBackend()..fail = true;
    final recovery = ReceiptRecovery(backend);
    await expectLater(
      recovery.recoverOnce(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await recovery.recoverOnce(), isNull);
    expect(backend.attempts, 1);
  });
  test('cancelled camera cache cleaned; earlier files and gallery original preserved', () async {
    final root = await Directory.systemTemp.createTemp('ledgy-camera-cache-');
    addTearDown(() async {
      final resolved = await root.resolveSymbolicLinks();
      if (!p.isWithin(
        await Directory.systemTemp.resolveSymbolicLinks(),
        resolved,
      )) {
        throw StateError('Unexpected test directory');
      }
      await root.delete(recursive: true);
    });
    final cache = await Directory(p.join(root.path, 'cache')).create();
    Future<File> image(String name) =>
        File(p.join(cache.path, name)).writeAsBytes([1, 2, 3]);
    final earlier = await image('11111111-1111-4111-8111-111111111111123.jpg');
    final original = await File(p.join(root.path, 'gallery-original.jpg'))
        .writeAsBytes([4, 5]);
    final unrelated = await image('user-photo.jpg');
    final before = await cameraCacheFiles(cache);
    final cancelled = await image(
      '22222222-2222-4222-8222-222222222222987.jpg',
    );
    await clearCameraCache(cache, preserve: before);
    expect(await cancelled.exists(), isFalse);
    expect(await earlier.exists(), isTrue);
    expect(await original.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });
}
