import 'dart:typed_data';

/// Native platforms — clipboard is always available.
bool get isClipboardAvailablePlatform => true;

/// Native platforms — Flutter's clipboard holds text only, and no image
/// clipboard plugin is bundled yet (#3436), so a photo cannot be copied.
bool get isImageClipboardAvailablePlatform => false;

/// Native platforms have no image clipboard; see
/// [isImageClipboardAvailablePlatform].
Future<void> writeClipboardImagePlatform(Future<Uint8List> png) =>
    Future.error(UnsupportedError('No image clipboard on this platform'));
