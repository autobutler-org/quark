/// Reads a 3D model about to be uploaded for its thumbnail (#3227), from
/// wherever the platform holds it: a path on disk natively, a `Blob` on the
/// web, which has no paths. Each hands the bytes to
/// `ModelThumbnailService.renderForUpload`, which never reads a file over
/// the viewer's caps.
library;

export 'package:quark/services/model_thumbnail_source_io.dart'
    if (dart.library.js_interop) 'package:quark/services/model_thumbnail_source_web.dart';
