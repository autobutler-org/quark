import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/image_rendition.dart';

/// #3436: a photo goes on the clipboard as a PNG bounded in size.
void main() {
  Future<Uint8List> png(int width, int height) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF008080),
    );
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<(int, int)> sizeOf(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final size = (image.width, image.height);
    image.dispose();
    return size;
  }

  bool isPng(Uint8List bytes) =>
      bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;

  testWidgets('shrinks a wide photo to the longest-side bound', (tester) async {
    await tester.runAsync(() async {
      final out = await pngRendition(await png(400, 100), maxDimension: 200);

      expect(isPng(out), isTrue);
      expect(await sizeOf(out), (200, 50));
    });
  });

  testWidgets('shrinks a tall photo by its height', (tester) async {
    await tester.runAsync(() async {
      final out = await pngRendition(await png(100, 400), maxDimension: 200);

      expect(await sizeOf(out), (50, 200));
    });
  });

  testWidgets('keeps a small photo at its size', (tester) async {
    await tester.runAsync(() async {
      final out = await pngRendition(await png(120, 80), maxDimension: 200);

      expect(isPng(out), isTrue);
      expect(await sizeOf(out), (120, 80));
    });
  });

  testWidgets('throws on bytes that are not an image', (tester) async {
    await tester.runAsync(() async {
      await expectLater(
        pngRendition(Uint8List.fromList([1, 2, 3])),
        throwsA(anything),
      );
    });
  });
}
