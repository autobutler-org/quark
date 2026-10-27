import 'dart:js_interop';
import 'dart:typed_data';

import 'package:quark/services/model_thumbnail_service.dart';
import 'package:web/web.dart' as web;

/// The web has no file paths.
Future<Uint8List?> renderModelThumbnailFromPath(
  String name,
  String path,
) async => null;

/// The thumbnail of the model [name] the browser holds as [blob], or null.
Future<Uint8List?> renderModelThumbnailFromBlob(web.Blob blob, String name) =>
    ModelThumbnailService.instance.renderForUpload(
      name: name,
      length: () async => blob.size,
      read: () async => (await blob.arrayBuffer().toDart).toDart.asUint8List(),
    );
