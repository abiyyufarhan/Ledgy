import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/receipt/ocr_line.dart';
import '../domain/receipt/receipt_scan_backend.dart';
import 'receipt_image_preprocessor.dart';
import 'receipt_camera_cache.dart';

final class MlKitReceiptBackend implements ReceiptScanBackend {
  final _picker = ImagePicker();
  Future<Directory> _directory() async => Directory(
    p.join((await getTemporaryDirectory()).path, 'ledgy_2_receipt_scan'),
  ).create(recursive: true);
  void _checkAndroid() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const FormatException('Pemindaian struk tersedia di Android');
    }
  }

  Future<void> _removePickerCache(XFile file) async {
    // Never delete a gallery original: only this app's copied picker cache.
    final cache = p.normalize((await getTemporaryDirectory()).path);
    if (p.isWithin(cache, p.normalize(file.path))) {
      final owned = File(file.path);
      if (await owned.exists()) await owned.delete();
    }
  }

  Future<ReceiptPhoto> _prepare(XFile file) async {
    File? target;
    try {
      final bytes = await compute(
        prepareReceiptImage,
        await file.readAsBytes(),
      );
      target = File(
        p.join((await _directory()).path, '${const Uuid().v4()}.jpg'),
      );
      await target.writeAsBytes(bytes, flush: true);
      return ReceiptPhoto(target.path, bytes);
    } catch (_) {
      if (target != null && await target.exists()) await target.delete();
      rethrow;
    } finally {
      await _removePickerCache(file);
    }
  }

  @override
  Future<ReceiptPhoto?> pick(ReceiptImageSource source) async {
    _checkAndroid();
    final cameraCache = source == ReceiptImageSource.camera
        ? await getTemporaryDirectory()
        : null;
    final before = cameraCache == null
        ? <String>{}
        : await cameraCacheFiles(cameraCache);
    try {
      final image = await _picker.pickImage(
        source: source == ReceiptImageSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        requestFullMetadata: false,
        // Resize our owned copy in the isolate. Native gallery resizing leaves
        // an extra, unreturned cache image that we could not reliably delete.
      );
      return image == null ? null : await _prepare(image);
    } finally {
      if (cameraCache != null) {
        await clearCameraCache(cameraCache, preserve: before);
      }
    }
  }

  @override
  Future<ReceiptPhoto?> recover() async {
    _checkAndroid();
    // Previous process cannot still own any files in this private scan folder.
    final directory = await _directory();
    await for (final file in directory.list()) {
      if (file is File && p.extension(file.path) == '.jpg') await file.delete();
    }
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.exception != null) throw lost.exception!;
      final files = lost.files;
      if (files == null || files.isEmpty) return null;
      for (final file in files.skip(1)) {
        await _removePickerCache(file);
      }
      return await _prepare(files.first);
    } finally {
      // Resolve a recovered selection first, then clear camera leftovers from
      // the previous process (our prepared previews live in a separate folder).
      await clearCameraCache(await getTemporaryDirectory());
    }
  }

  @override
  Future<List<OcrLine>> recognize(ReceiptPhoto photo) async {
    _checkAndroid();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      return [
        for (final block in text.blocks)
          for (final line in block.lines)
            OcrLine(
              text: line.text,
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
            ),
      ];
    } finally {
      await recognizer.close();
    }
  }

  @override
  Future<void> remove(ReceiptPhoto photo) async {
    final directory = await _directory();
    if (!p.isWithin(p.normalize(directory.path), p.normalize(photo.path))) {
      return;
    }
    final file = File(photo.path);
    if (await file.exists()) await file.delete();
  }
}
