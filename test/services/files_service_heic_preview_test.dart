import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

/// A HEIC opens from the preview its client uploaded, not from the Quark
/// decoding it (#2379).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Uri> requested;

  /// Answers the preview request with [preview] and the download with
  /// [download].
  void answer(int preview, {int download = 200}) {
    requested = [];
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requested.add(request.url);
      final status = request.url.path.startsWith('/api/v0/thumbnails/')
          ? preview
          : download;
      return http.Response.bytes(Uint8List.fromList([1, 2]), status);
    });
  }

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('a HEIC loads its stored preview', () async {
    answer(200);

    final bytes = await FilesService.downloadFileBytes(
      'trips/IMG_1.HEIC',
      serial: 'sd1',
    );

    expect(bytes, [1, 2]);
    expect(requested.single.path, '/api/v0/thumbnails/trips/IMG_1.HEIC');
    expect(requested.single.queryParameters['size'], 'preview');
    expect(requested.single.queryParameters['serial'], 'sd1');
    expect(requested.single.queryParameters.containsKey('format'), isFalse);
  });

  test('a HEIC without a preview falls back to the Quark\'s JPEG', () async {
    answer(404);

    final bytes = await FilesService.downloadFileBytes(
      'trips/IMG_1.heic',
      serial: 'sd1',
    );

    expect(bytes, [1, 2]);
    expect(requested, hasLength(2));
    expect(requested.last.path, '/api/v0/files/download');
    expect(requested.last.queryParameters['format'], 'jpeg');
    expect(requested.last.queryParameters['serial'], 'sd1');
  });

  test('a HEIC neither has says to download the original', () async {
    answer(404, download: 404);

    final error = await FilesService.downloadFileBytes(
      'trips/IMG_1.heic',
      serial: 'sd1',
    ).then<Object?>((_) => null, onError: (e) => e);

    expect(error, isA<NoPreviewException>());
    final noPreview = error! as NoPreviewException;
    expect(noPreview.path, 'trips/IMG_1.heic');
    expect(noPreview.serial, 'sd1');
    expect(noPreview.name, 'IMG_1.heic');
    expect(Errors.message(error, 'load the photo'), Errors.noPreview);
  });

  test('a failing preview request is not taken for a missing one', () async {
    answer(503);

    final error = await FilesService.downloadFileBytes(
      'trips/IMG_1.heic',
    ).then<Object?>((_) => null, onError: (e) => e);

    expect(error, isA<ApiException>());
    expect(requested, hasLength(1));
  });

  test('a TIFF still asks the Quark for a JPEG', () async {
    answer(200);

    await FilesService.downloadFileBytes('scan.tiff');

    expect(requested.single.path, '/api/v0/files/download');
    expect(requested.single.queryParameters['format'], 'jpeg');
  });
}
