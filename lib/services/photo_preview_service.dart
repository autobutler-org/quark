import 'dart:typed_data';

import 'package:quark/services/files_service.dart';
import 'package:quark/services/photo_disk_cache.dart';
import 'package:quark/utils/error_text.dart';

/// Fetches a photo's screen-sized preview: the whole photo, uncropped, its
/// long edge at most 2048 px, as a JPEG of a few hundred KB (#4220).
///
/// The photo viewer shows this first and downloads the original only when
/// the user zooms in, so opening a photo costs a fraction of the 2-25 MB an
/// original runs to. The preview has the file's EXIF orientation applied and
/// not the user's rotation, exactly as the original decodes, so the viewer
/// turns either one the same way and can swap one for the other in place.
abstract final class PhotoPreviewService {
  /// The preview of the photo at [filePath] on the device [serial].
  ///
  /// Throws [ApiException] when the Quark answers without one — a 404 for a
  /// photo it cannot render, such as a HEIC, among them — so the caller can
  /// fall back to the original.
  ///
  /// A preview is kept among the device's previews (#4221), never under the
  /// original's key, so a photo viewed before opens with no network.
  ///
  /// api: GET /api/v0/thumbnails/{filePath}
  static Future<Uint8List?> downloadPreviewBytes(
    String filePath, {
    String? serial,
  }) => PhotoDiskCache.preview(
    filePath,
    serial: serial,
    download: () async {
      final uri = FilesService.constructThumbnailUrl(
        filePath,
        serial: serial,
        size: 'preview',
      );
      final response = await FilesService.instance.authenticatedGet(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(response.statusCode, 'Failed to load the preview');
      }
      return response.bodyBytes;
    },
  );
}
