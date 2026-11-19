import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/files_service.dart';

import '../support/fake_quark_http.dart';

/// #3428: the Photos library lists videos beside photos, so the client asks
/// the photos list for them; the Quark keeps them out unless asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  test('asks the photos list for videos too', () async {
    answer(200, {'photos': <Object>[], 'total': 0});

    await FilesService.getPhotos();

    expect(requests.single.url.path, '/api/v0/photos');
    expect(requests.single.url.queryParameters['includeVideos'], 'true');
  });
}
