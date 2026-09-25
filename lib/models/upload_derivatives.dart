import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The thumbnail and display preview a client renders for a photo or video it
/// uploads, so the Quark never has to decode the file itself (#2379).
///
/// Both are JPEGs with rotation already applied. [thumbnail] has a long edge
/// of at most 400, the largest size the Quark serves; [preview], rendered only
/// for HEIC and video, about 2048.
class UploadDerivatives {
  const UploadDerivatives({required this.thumbnail, this.preview});

  final Uint8List thumbnail;
  final Uint8List? preview;

  /// The sidecar parts that follow the file named [fileName] in a multipart
  /// upload. The Quark pairs a part to its file by this filename, so each
  /// must come after the file it belongs to.
  List<http.MultipartFile> sidecarParts(String fileName) => [
    http.MultipartFile.fromBytes('thumbnail', thumbnail, filename: fileName),
    if (preview case final preview?)
      http.MultipartFile.fromBytes('preview', preview, filename: fileName),
  ];
}
