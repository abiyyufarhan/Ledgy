// Run: flutter test tool/generate_brand_assets.dart
// These generated assets have no runtime dependency or downloaded artwork.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/core/branding/ledgy_mark.dart';

Future<Uint8List> render(int pixels, {bool opaque = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (opaque) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pixels.toDouble(), pixels.toDouble()),
      Paint()..color = LedgyBrand.background,
    );
  }
  const LedgyMarkPainter().paint(canvas, Size.square(pixels.toDouble()));
  final picture = recorder.endRecording();
  final bitmap = await picture.toImage(pixels, pixels);
  final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
  bitmap.dispose();
  picture.dispose();
  return png!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Generate original Ledgy launcher assets', () async {
    Future<void> save(String path, List<int> bytes) async {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }

    for (final item in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      await save(
        'android/app/src/main/res/mipmap-${item.key}/ic_launcher.png',
        await render(item.value),
      );
    }
    await save('assets/branding/ledgy-icon-1024.png', await render(1024));
    await save(
      'assets/branding/ledgy-play-store-512.png',
      await render(512, opaque: true),
    );
    await save('linux/runner/resources/ledgy.png', await render(256));

    // ICO embeds multiple lossless PNG frames for crisp Windows scaling.
    final sizes = [16, 24, 32, 48, 64, 128, 256];
    final frames = <Uint8List>[];
    for (final size in sizes) {
      frames.add(await render(size));
    }
    final header = ByteData(6 + sizes.length * 16);
    header.setUint16(2, 1, Endian.little);
    header.setUint16(4, sizes.length, Endian.little);
    var offset = header.lengthInBytes;
    for (var i = 0; i < sizes.length; i++) {
      final row = 6 + i * 16;
      header.setUint8(row, sizes[i] == 256 ? 0 : sizes[i]);
      header.setUint8(row + 1, sizes[i] == 256 ? 0 : sizes[i]);
      header.setUint16(row + 4, 1, Endian.little);
      header.setUint16(row + 6, 32, Endian.little);
      header.setUint32(row + 8, frames[i].length, Endian.little);
      header.setUint32(row + 12, offset, Endian.little);
      offset += frames[i].length;
    }
    final ico = BytesBuilder()..add(header.buffer.asUint8List());
    for (final frame in frames) {
      ico.add(frame);
    }
    await save('windows/runner/resources/app_icon.ico', ico.takeBytes());
  });
}
