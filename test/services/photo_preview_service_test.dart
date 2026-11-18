import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/photo_preview_service.dart';
import 'package:quark/utils/error_text.dart';

/// The viewer's preview is the thumbnails endpoint's `preview` size (#4220).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uri requested;
  void answer(int status, List<int> body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requested = request.url;
      return http.Response.bytes(body, status);
    });
  }

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('asks for the preview size of the photo on its drive', () async {
    answer(200, [1, 2, 3]);
    final bytes = await PhotoPreviewService.downloadPreviewBytes(
      'Trips/a b.jpg',
      serial: 'sd1',
    );
    expect(bytes, [1, 2, 3]);
    expect(requested.path, '/api/v0/thumbnails/Trips/a%20b.jpg');
    expect(requested.queryParameters['size'], 'preview');
    expect(requested.queryParameters['serial'], 'sd1');
  });

  test('a photo the Quark cannot preview is an ApiException', () async {
    answer(404, []);
    await expectLater(
      PhotoPreviewService.downloadPreviewBytes('a.heic'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });
}
