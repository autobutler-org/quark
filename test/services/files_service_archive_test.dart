import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  /// Answers every request with [bytes] served as [contentType].
  void answer(String contentType, List<int> bytes) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': contentType},
      );
    });
  }

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('asks for a JPEG of a TIFF entry and reports one', () async {
    answer('image/jpeg', [0xff, 0xd8]);

    final entry = await FilesService.downloadArchiveFileBytes(
      'photos.zip',
      'pics/scan.TIFF',
      convertImages: true,
    );

    expect(requests.single.url.queryParameters['format'], 'jpeg');
    expect(entry.isJpeg, isTrue);
    expect(entry.bytes, Uint8List.fromList([0xff, 0xd8]));
  });

  // The Quark decodes no HEIC (#2382), so asking it for a JPEG is pointless.
  test('never asks for a JPEG of a HEIC entry', () async {
    answer('application/octet-stream', [1]);

    await FilesService.downloadArchiveFileBytes(
      'photos.zip',
      'pics/IMG_1.HEIC',
      convertImages: true,
    );

    expect(requests.single.url.queryParameters.containsKey('format'), isFalse);
  });

  // A viewer shows a HEIC through the thumbnail a client rendered (#2382).
  test('loads a HEIC photo from its stored thumbnail', () async {
    answer('image/jpeg', [0xff, 0xd8]);

    final bytes = await FilesService.downloadFileBytes(
      'Camera/IMG_1.HEIC',
      serial: 'S1',
    );

    final url = requests.single.url;
    expect(url.path, '/api/v0/thumbnails/Camera/IMG_1.HEIC');
    expect(url.queryParameters['size'], 'lg');
    expect(url.queryParameters['serial'], 'S1');
    expect(bytes, Uint8List.fromList([0xff, 0xd8]));
  });

  // An older Quark ignores format=jpeg and sends the original bytes, which the
  // image viewer cannot draw, so the page must fall back to a download (#1851).
  test('reports original bytes from an older server as not JPEG', () async {
    answer('application/octet-stream', [1, 2, 3]);

    final entry = await FilesService.downloadArchiveFileBytes(
      'photos.zip',
      'pics/scan.tiff',
      convertImages: true,
    );

    expect(requests.single.url.queryParameters['format'], 'jpeg');
    expect(entry.isJpeg, isFalse);
    expect(entry.bytes, Uint8List.fromList([1, 2, 3]));
  });

  test('never asks for a conversion unless told to', () async {
    answer('application/octet-stream', [1]);

    await FilesService.downloadArchiveFileBytes('photos.zip', 'IMG_1.heic');
    await FilesService.downloadArchiveFileBytes(
      'photos.zip',
      'notes.txt',
      convertImages: true,
    );

    for (final request in requests) {
      expect(request.url.queryParameters.containsKey('format'), isFalse);
    }
  });
}
