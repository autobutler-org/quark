import 'dart:ui' as ui;

import 'quark_model_camera.dart';
import 'quark_model_mesh.dart';
import 'quark_model_viewer/model_renderer.dart';

/// Draws [mesh] off-screen into a [size] x [size] image, as the viewer first
/// shows it: shaded in [color] over [background], from
/// [QuarkModelCamera.initial]. A mesh with a preview draws the preview,
/// which is all a picture this small can show. An empty mesh is just
/// [background]. The caller disposes the image.
///
/// ```dart
/// final image = await renderQuarkModelImage(
///   mesh,
///   size: 400,
///   color: tokens.primary,
///   background: tokens.card,
/// );
/// ```
Future<ui.Image> renderQuarkModelImage(
  QuarkModelMesh mesh, {
  required int size,
  required ui.Color color,
  required ui.Color background,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..drawColor(background, ui.BlendMode.src);
  ModelRenderer(mesh.preview ?? mesh).paint(
    canvas,
    ui.Size(size.toDouble(), size.toDouble()),
    QuarkModelCamera.initial,
    color: color,
    edgeColor: color,
  );
  final picture = recorder.endRecording();
  return picture.toImage(size, size).whenComplete(picture.dispose);
}
