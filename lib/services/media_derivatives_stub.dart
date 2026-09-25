import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:quark/models/upload_derivatives.dart';

/// No renderer on this platform yet, so nothing is rendered and the Quark
/// makes what thumbnail it can, as it does for an older client.
Future<UploadDerivatives?> renderDerivativesFromBytesPlatform(
  String name,
  Uint8List bytes,
) async => null;

/// See [renderDerivativesFromBytesPlatform].
Future<UploadDerivatives?> renderDroppedFileDerivativesPlatform(
  DropItemFile file,
) async => null;
