import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Sizing for the image a photo becomes on the system clipboard (#3436).
abstract final class ClipboardImageConfig {
  /// The longest side, in pixels, of a photo copied to the clipboard.
  ///
  /// A clipboard PNG is uncompressed enough that a 48 MP original would run
  /// to tens of megabytes and stall the paste; 2048 px is sharp in a chat,
  /// an email or a document and stays a few megabytes.
  static const int maxDimension = 2048;
}

/// Decodes [encoded] (any format Flutter's decoder reads) and re-encodes it
/// as a PNG whose longest side is at most [maxDimension], keeping the aspect
/// ratio. A smaller image keeps its size.
///
/// PNG because it is the one image type every browser's clipboard accepts
/// and every app pastes. Throws when [encoded] cannot be decoded.
Future<Uint8List> pngRendition(
  Uint8List encoded, {
  int maxDimension = ClipboardImageConfig.maxDimension,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      if (math.max(width, height) <= maxDimension) {
        return ui.TargetImageSize(width: width, height: height);
      }
      return width >= height
          ? ui.TargetImageSize(width: maxDimension)
          : ui.TargetImageSize(height: maxDimension);
    },
  );
  final ui.Image image;
  try {
    image = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('PNG encoding returned no data');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
