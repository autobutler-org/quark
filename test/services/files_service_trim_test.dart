import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('queues the trim and returns its job id', () async {
    late http.Request sent;
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      sent = request;
      return http.Response(jsonEncode({'jobId': 42}), 202);
    });

    final id = await FilesService.trimVideo(
      'videos/a.mp4',
      serial: ' usb1 ',
      startMs: 1000,
      endMs: 5000,
    );

    expect(id, 42);
    expect(sent.url.path, '/api/v0/videos/trim');
    expect(jsonDecode(sent.body), {
      'relPath': 'videos/a.mp4',
      'serial': 'usb1',
      'startMs': 1000,
      'endMs': 5000,
    });
  });

  test('a refusal throws an ApiException with its status', () async {
    resetSharedHttpClient();
    sharedHttpClientFactory = () =>
        MockClient((request) async => http.Response('{}', 422));

    expect(
      FilesService.trimVideo('videos/a.mp4', startMs: 0, endMs: 1000),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
    );
  });
}
