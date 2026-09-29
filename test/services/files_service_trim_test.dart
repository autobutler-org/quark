import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('returns the saved clip and where it really starts', () async {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient(
      (request) async => http.Response(
        jsonEncode({'relPath': 'videos/a_trim.mp4', 'actualStartMs': 800}),
        200,
      ),
    );

    final result = await FilesService.trimVideo(
      'videos/a.mp4',
      startMs: 1000,
      endMs: 5000,
    );

    expect(result.relPath, 'videos/a_trim.mp4');
    expect(result.actualStart, const Duration(milliseconds: 800));
  });
}
