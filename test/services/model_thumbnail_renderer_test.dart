import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quark/services/model_thumbnail_renderer.dart';
import 'package:quark/utils/model_thumbnail_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A cube centered on the origin, twelve triangles.
QuarkModelMesh cube() {
  final positions = Float32List.fromList([
    -1, -1, -1, 1, -1, -1, 1, 1, -1, -1, 1, -1, //
    -1, -1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1,
  ]);
  final indices = Uint32List.fromList([
    0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, //
    0, 1, 5, 0, 5, 4, 3, 7, 6, 3, 6, 2,
    0, 4, 7, 0, 7, 3, 1, 2, 6, 1, 6, 5,
  ]);
  return QuarkModelMesh.fromTriangles(positions: positions, indices: indices);
}

/// `renderModelThumbnail` (#3227): the off-screen draw is the JPEG the Quark
/// takes, and it shows the model.
void main() {
  testWidgets('draws the model into a square JPEG', (tester) async {
    final jpeg = await tester.runAsync(() => renderModelThumbnail(cube()));
    expect(jpeg, isNotNull);
    // A JPEG's start-of-image marker, which the Quark checks for.
    expect(jpeg!.sublist(0, 2), [0xFF, 0xD8]);

    final decoded = img.decodeJpg(jpeg)!;
    expect(decoded.width, ModelThumbnailConfig.edge);
    expect(decoded.height, ModelThumbnailConfig.edge);

    const background = ModelThumbnailConfig.background;
    bool isBackground(img.Pixel p) =>
        (p.r - background.r * 255).abs() < 8 &&
        (p.g - background.g * 255).abs() < 8 &&
        (p.b - background.b * 255).abs() < 8;
    const middle = ModelThumbnailConfig.edge ~/ 2;
    expect(isBackground(decoded.getPixel(2, 2)), isTrue);
    expect(isBackground(decoded.getPixel(middle, middle)), isFalse);
  });

  testWidgets('an empty mesh has nothing to draw', (tester) async {
    final empty = QuarkModelMesh.fromTriangles(
      positions: Float32List(0),
      indices: Uint32List(0),
    );
    expect(await tester.runAsync(() => renderModelThumbnail(empty)), isNull);
  });
}
