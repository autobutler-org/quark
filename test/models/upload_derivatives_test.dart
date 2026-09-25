import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/upload_derivatives.dart';

void main() {
  test('names each sidecar for its kind and pairs it by the file name', () {
    final parts = UploadDerivatives(
      thumbnail: Uint8List.fromList([1]),
      preview: Uint8List.fromList([2, 3]),
    ).sidecarParts('clip.mov');

    expect([for (final p in parts) p.field], ['thumbnail', 'preview']);
    expect([for (final p in parts) p.filename], ['clip.mov', 'clip.mov']);
    expect([for (final p in parts) p.length], [1, 2]);
  });

  test('sends no preview part without a preview', () {
    final parts = UploadDerivatives(
      thumbnail: Uint8List.fromList([1]),
    ).sidecarParts('photo.jpg');
    expect([for (final p in parts) p.field], ['thumbnail']);
  });
}
