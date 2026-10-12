import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ledgy/features/quick_input/data/receipt_image_preprocessor.dart';

void main() {
  test('EXIF orientation baked before 1600px resize; metadata removed', () {
    final image = img.Image(width: 2000, height: 1000);
    image.exif.imageIfd.orientation = 6;
    final output = img.decodeJpg(
      prepareReceiptImage(Uint8List.fromList(img.encodeJpg(image))),
    )!;
    expect(output.width, 800);
    expect(output.height, 1600);
    expect(output.exif.imageIfd.orientation, isNot(6));
  });
  test('small images retain resolution', () {
    final output = img.decodeJpg(
      prepareReceiptImage(img.encodePng(img.Image(width: 300, height: 600))),
    )!;
    expect(output.width, 300);
    expect(output.height, 600);
  });
  test('undecodable input rejected without OCR', () {
    expect(
      () => prepareReceiptImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
