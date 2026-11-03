import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:quark/utils/model_thumbnail_config.dart';
import 'package:quark_widgets/quark_widgets.dart'
    show ModelRenderer, QuarkModelMesh;

/// Draws [mesh] off-screen with the viewer's own [ModelRenderer] (#3227) and
/// encodes it as the JPEG the Quark takes for a client thumbnail: a
/// [ModelThumbnailConfig.edge] square, the model shaded from the viewer's
/// opening view on a neutral backdrop. A mesh carrying a preview is drawn
/// from the preview, which at this size looks the same and draws in a
/// fraction of the time. Null for an empty mesh, which has nothing to show.
Future<Uint8List?> renderModelThumbnail(QuarkModelMesh mesh) async {
  final drawn = mesh.preview ?? mesh;
  if (drawn.isEmpty) return null;
  const edge = ModelThumbnailConfig.edge;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(ModelThumbnailConfig.background, ui.BlendMode.src);
  ModelRenderer(drawn).paint(
    canvas,
    const ui.Size(edge + 0.0, edge + 0.0),
    ModelThumbnailConfig.camera,
    color: ModelThumbnailConfig.modelColor,
    edgeColor: ModelThumbnailConfig.modelColor,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(edge, edge);
  picture.dispose();
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;
    return await compute(_encodeJpeg, rgba.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Uint8List _encodeJpeg(Uint8List rgba) => img.encodeJpg(
  img.Image.fromBytes(
    width: ModelThumbnailConfig.edge,
    height: ModelThumbnailConfig.edge,
    bytes: rgba.buffer,
    numChannels: 4,
  ),
  quality: ModelThumbnailConfig.jpegQuality,
);
