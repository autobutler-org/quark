import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/services/upload_batch.dart';

/// A one-byte picked photo with no path on disk, so it uploads from bytes.
final class _Picked extends PlatformFile {
  _Picked(this.name);

  @override
  final String name;

  final Uint8List _bytes = Uint8List.fromList([1]);

  @override
  Uri get uri => Uri.parse('memory:$name');

  // The controller never asks for one, and cross_file is not a dependency
  // of the app to name its type.
  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

/// An import the Quark cut off partway is finished without a second copy of
/// the photos that already landed (#3533).
void main() {
  test('a photo import resends only the photos that did not land', () async {
    final requests = <List<String>>[];
    var call = 0;
    final controller = PhotosController(
      isWeb: true,
      renderFromBytes: (name, bytes) async => null,
      uploadFiles:
          (
            path,
            List<http.MultipartFile> files, {
            serial,
            overwrite = false,
            keepBoth = false,
          }) async {
            requests.add([for (final f in files) f.filename!]);
            if (call++ == 0) {
              throw const UploadBatchFailure(400, ['a.jpg', 'b.jpg']);
            }
            return ['c.jpg'];
          },
      addPhotoToAlbum:
          (albumId, {required deviceSerial, required relPath}) async => true,
    );

    final outcome = await controller.uploadPhotos([
      _Picked('a.jpg'),
      _Picked('b.jpg'),
      _Picked('c.jpg'),
    ], albumId: 1);

    expect(requests, [
      ['a.jpg', 'b.jpg', 'c.jpg'],
      ['c.jpg'],
    ]);
    expect((outcome!.added, outcome.failed), (3, 0));
  });

  test(
    'a dropped photo that landed before its thumbnail broke counts as sent',
    () async {
      var calls = 0;
      final controller = PhotosController(
        isWeb: true,
        readDroppedFile: (file) async => Uint8List.fromList([1]),
        renderDroppedFile: (file) async => Uint8List.fromList([2]),
        uploadFiles:
            (path, files, {serial, overwrite = false, keepBoth = false}) async {
              calls++;
              throw const UploadBatchFailure(400, ['a.jpg']);
            },
      );
      final (:photos, notPhotos: _) = controller.sortDroppedFiles([
        DropItemFile.fromData(Uint8List.fromList([1]), path: 'a.jpg'),
      ]);

      final uploaded = await controller.uploadDroppedPhotos(photos);

      expect(calls, 1);
      expect(uploaded, 1);
    },
  );
}
