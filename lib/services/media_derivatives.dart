/// Renders the thumbnail and display preview a photo or video carries with it
/// when it is uploaded (#2379), with the platform's own decoders, so the Quark
/// never decodes H.264, HEVC or HEIC itself.
///
/// Every function here returns null rather than throwing when it cannot
/// render: the file uploads either way, and one without derivatives gets
/// whatever the Quark can make of it, as from an older client.
///
/// The web renders with the browser (`createImageBitmap` for photos, a
/// `<video>` element for video). iOS and Android render nothing yet: they need
/// a platform plugin for video frames and HEIC, which is still to be chosen.
library;

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:quark/models/upload_derivatives.dart';
import 'package:quark/services/media_derivatives_stub.dart'
    if (dart.library.js_interop) 'package:quark/services/media_derivatives_web.dart'
    as platform;

/// Derivatives for the file [name] whose bytes are already in memory.
Future<UploadDerivatives?> renderDerivativesFromBytes(
  String name,
  Uint8List bytes,
) => platform.renderDerivativesFromBytesPlatform(name, bytes);

/// Derivatives for a file that arrived by drag and drop.
Future<UploadDerivatives?> renderDroppedFileDerivatives(DropItemFile file) =>
    platform.renderDroppedFileDerivativesPlatform(file);
