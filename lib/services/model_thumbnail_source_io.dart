import 'dart:io';
import 'dart:typed_data';

import 'package:quark/services/model_thumbnail_service.dart';

/// The thumbnail of the model [name] on disk at [path], or null.
Future<Uint8List?> renderModelThumbnailFromPath(String name, String path) {
  final file = File(path);
  return ModelThumbnailService.instance.renderForUpload(
    name: name,
    length: file.length,
    read: file.readAsBytes,
  );
}
