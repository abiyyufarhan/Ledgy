import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Run on an isolate; bake EXIF before resizing and strip metadata on encoding.
Uint8List prepareReceiptImage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException(
      'Format foto tidak didukung. Pilih JPG atau PNG.',
    );
  }
  if (decoded == null) {
    throw const FormatException(
      'Format foto tidak didukung. Pilih JPG atau PNG.',
    );
  }
  var image = img.bakeOrientation(decoded);
  if (image.width > 1600 || image.height > 1600) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1600 : null,
      height: image.height > image.width ? 1600 : null,
      interpolation: img.Interpolation.average,
    );
  }
  image.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}
