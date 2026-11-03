import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The ARGB of the pixel at [x], [y] of [image].
Future<int> pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData())!;
  final i = (y * image.width + x) * 4;
  final r = data.getUint8(i), g = data.getUint8(i + 1);
  final b = data.getUint8(i + 2), a = data.getUint8(i + 3);
  return a << 24 | r << 16 | g << 8 | b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const background = ui.Color(0xff102030);
  const color = ui.Color(0xffe0a040);

  // A cube's worth of points as two crossed squares: something at the
  // center of the frame from any side.
  final mesh = QuarkModelMesh.fromTriangles(
    positions: Float32List.fromList([
      -1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0, //
      0, -1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1,
    ]),
    indices: Uint32List.fromList([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7]),
  );

  test('draws the model over the background at the size asked', () async {
    final image = await renderQuarkModelImage(
      mesh,
      size: 64,
      color: color,
      background: background,
    );
    addTearDown(image.dispose);
    expect((image.width, image.height), (64, 64));
    expect(await pixel(image, 0, 0), background.toARGB32());
    expect(await pixel(image, 32, 32), isNot(background.toARGB32()));
  });

  test('an empty mesh is only the background', () async {
    final image = await renderQuarkModelImage(
      QuarkModelMesh.fromTriangles(
        positions: Float32List(0),
        indices: Uint32List(0),
      ),
      size: 16,
      color: color,
      background: background,
    );
    addTearDown(image.dispose);
    expect(await pixel(image, 8, 8), background.toARGB32());
  });
}
