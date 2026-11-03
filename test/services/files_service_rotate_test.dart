import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('asks the Quark for one quarter turn clockwise', () async {
    resetSharedHttpClient();
    late http.Request sent;
    sharedHttpClientFactory = () => MockClient((request) async {
      sent = request;
      return http.Response(jsonEncode({'orientation': 6}), 200);
    });

    await FilesService.rotatePhoto('photos/a.jpg', serial: 'abc');

    expect(sent.url.path, '/api/v0/photos/rotate');
    expect(jsonDecode(sent.body), {
      'relPath': 'photos/a.jpg',
      'serial': 'abc',
      'quarters': 1,
    });
  });

  test('a 422 reads as only JPEGs being turnable', () async {
    resetSharedHttpClient();
    sharedHttpClientFactory = () =>
        MockClient((request) async => http.Response('{}', 422));

    await expectLater(
      FilesService.rotatePhoto('photos/a.png'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422),
      ),
    );
    expect(Errors.rotatePhoto(const ApiException(422)), Errors.cantRotatePhoto);
    expect(
      Errors.rotatePhoto(const ApiException(500)),
      Errors.message(const ApiException(500), 'rotate the photo'),
    );
  });

  test('photo metadata carries no rotation', () {
    final meta = PhotoMetadata.fromJson({
      'fileName': 'a.jpg',
      'fileSize': 1,
      'mtime': 1,
      'width': 2,
      'height': 3,
      'isFavorite': false,
      'albums': <dynamic>[],
    });
    expect(meta.fileName, 'a.jpg');
  });
}
