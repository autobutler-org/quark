import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/photo_jpeg_download.dart';

/// #4188: "Download as JPEG" fetches the original, converts it on this
/// device, and saves the JPEG; when the device cannot convert it, the
/// original is saved instead and the caller is told so.
void main() {
  final heic = Uint8List.fromList([1, 2, 3]);
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);

  test('saves the converted JPEG under a .jpg name', () async {
    final saved = <(String, Uint8List)>[];
    final outcome = await downloadPhotoAsJpeg(
      path: 'Photos/IMG_0001.HEIC',
      serial: 'sd1',
      name: 'IMG_0001.HEIC',
      fetch: (path, {serial}) async {
        expect(path, 'Photos/IMG_0001.HEIC');
        expect(serial, 'sd1');
        return heic;
      },
      convert: (name, bytes) async => bytes == heic ? jpeg : null,
      save: (bytes, name) async {
        saved.add((name, bytes));
        return '/downloads/$name';
      },
    );
    expect(outcome.converted, isTrue);
    expect(outcome.fileName, 'IMG_0001.jpg');
    expect(outcome.savedAt, '/downloads/IMG_0001.jpg');
    expect(saved.single.$1, 'IMG_0001.jpg');
    // A HEIC without an Exif item has nothing to carry over.
    expect(saved.single.$2, jpeg);
  });

  test('saves the original, byte for byte, when it cannot convert', () async {
    final saved = <(String, Uint8List)>[];
    final outcome = await downloadPhotoAsJpeg(
      path: 'IMG_0002.heif',
      serial: null,
      name: 'IMG_0002.heif',
      fetch: (path, {serial}) async => heic,
      convert: (name, bytes) async => null,
      save: (bytes, name) async {
        saved.add((name, bytes));
        return name;
      },
    );
    expect(outcome.converted, isFalse);
    expect(outcome.fileName, 'IMG_0002.heif');
    expect(saved.single, ('IMG_0002.heif', heic));
  });

  test('a canceled save is reported as nothing saved', () async {
    final outcome = await downloadPhotoAsJpeg(
      path: 'a.heic',
      serial: null,
      name: 'a.heic',
      fetch: (path, {serial}) async => heic,
      convert: (name, bytes) async => jpeg,
      save: (bytes, name) async => null,
    );
    expect(outcome.savedAt, isNull);
  });

  test('jpegFileName swaps any extension for .jpg', () {
    expect(jpegFileName('IMG_0001.HEIC'), 'IMG_0001.jpg');
    expect(jpegFileName('a.b.heif'), 'a.b.jpg');
    expect(jpegFileName('IMG_0003'), 'IMG_0003.jpg');
  });

  test('offersJpegDownload is only for HEIC and HEIF', () {
    expect(offersJpegDownload('IMG.HEIC'), isTrue);
    expect(offersJpegDownload('IMG.heif'), isTrue);
    expect(offersJpegDownload('IMG.jpg'), isFalse);
    expect(offersJpegDownload('IMG.dng'), isFalse);
  });
}
