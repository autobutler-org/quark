/// Renders the thumbnail of a 3D model (#3227) off-screen with the model
/// viewer's own renderer, as a PNG with a long edge of 400 that the Quark
/// resizes into its thumbnail tiers.
///
/// Every function here returns null rather than throwing when it cannot
/// render: a model with no thumbnail shows its file icon.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/model_viewer_controller.dart';
import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The thumbnail of [mesh], a model already read.
Future<Uint8List?> renderModelThumbnail(QuarkModelMesh mesh) async {
  if (mesh.isEmpty) return null;
  final image = await renderQuarkModelImage(
    mesh,
    size: ClientThumbnailConfig.longEdge,
    color: ClientThumbnailConfig.modelColor,
    background: ClientThumbnailConfig.modelBackground,
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// The thumbnail of the model at [path] on [serial], read the way the viewer
/// reads it, so a file over the viewer's caps is never downloaded and
/// renders nothing.
Future<Uint8List?> renderModelFileThumbnail(
  String path, {
  String? serial,
}) async {
  final controller = ModelViewerController(
    path: path,
    serial: serial,
    // This is the save; it does not hand the mesh back to itself.
    saveThumbnail: (path, {serial, required mesh}) async => false,
  );
  try {
    await controller.load();
    final mesh = controller.mesh;
    if (mesh == null) {
      debugPrint(
        '[model_thumbnails.dart] No thumbnail for $path: '
        '${controller.fallback ?? controller.error}',
      );
      return null;
    }
    return await renderModelThumbnail(mesh);
  } finally {
    controller.dispose();
  }
}
