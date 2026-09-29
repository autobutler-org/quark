import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

/// The Quark's answer to a thumbnail request decides whether a client renders
/// one itself (#2381).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void answer(int status, String body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () =>
        MockClient((_) async => http.Response(body, status));
  }

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('a thumbnail is served', () async {
    answer(200, 'jpeg');
    final probe = await FilesService.probeThumbnail('a.mp4');
    expect(probe.served, isTrue);
    expect(probe.clientRender, isFalse);
  });

  test('a clientRender 404 carries the file version', () async {
    answer(
      404,
      jsonEncode({
        'error': 'no thumbnail',
        'clientRender': true,
        'modTime': '2026-09-24T10:00:00Z',
      }),
    );
    final probe = await FilesService.probeThumbnail('a.mp4', serial: 'sd1');
    expect(probe.served, isFalse);
    expect(probe.clientRender, isTrue);
    expect(probe.modTime, '2026-09-24T10:00:00Z');
  });

  test('a plain 404 is only missing', () async {
    answer(404, jsonEncode({'error': 'thumbnail not found'}));
    final probe = await FilesService.probeThumbnail('a.mp4');
    expect(probe.served, isFalse);
    expect(probe.clientRender, isFalse);
  });

  test('any other failure is an error', () async {
    answer(500, '');
    await expectLater(
      FilesService.probeThumbnail('a.mp4'),
      throwsA(isA<ApiException>()),
    );
  });
}
