import 'dart:typed_data';

import 'ocr_line.dart';

enum ReceiptImageSource { camera, gallery }

final class ReceiptPhoto {
  const ReceiptPhoto(this.path, this.preview);
  final String path;
  final Uint8List preview;
}

abstract interface class ReceiptScanBackend {
  Future<ReceiptPhoto?> pick(ReceiptImageSource source);
  Future<ReceiptPhoto?> recover();
  Future<List<OcrLine>> recognize(ReceiptPhoto photo);
  Future<void> remove(ReceiptPhoto photo);
}
