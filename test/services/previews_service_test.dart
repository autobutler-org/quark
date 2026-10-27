import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/previews_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `GET /previews/properties`: the metadata an office file saved about
/// itself (#3275).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  void respondWith(http.Response response) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return response;
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests.clear();
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('reads the properties object for the file', () async {
    respondWith(
      http.Response(
        jsonEncode({
          'title': 'Quarterly report',
          'author': 'Ada Lovelace',
          'words': 12,
          'slides': 4,
          'created': '2026-10-14T09:30:00Z',
          'countsSource': 'saved',
        }),
        200,
      ),
    );

    final properties = await PreviewsService.properties(
      'docs/report.odp',
      serial: 'usb1',
    );

    expect(properties.title, 'Quarterly report');
    expect(properties.author, 'Ada Lovelace');
    expect(properties.words, 12);
    expect(properties.slides, 4);
    expect(properties.created, DateTime.utc(2026, 10, 14, 9, 30));
    expect(properties.countsSource, 'saved');
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v0/previews/properties');
    expect(request.url.queryParameters['filePath'], 'docs/report.odp');
    expect(request.url.queryParameters['serial'], 'usb1');
  });

  test('a refusal is an ApiException and does not parse the body', () async {
    respondWith(http.Response('not json', 400));

    expect(
      PreviewsService.properties('docs/report.docx'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
    );
  });

  test('only formats the properties endpoint reads are asked', () {
    for (final name in [
      'a.docx',
      'a.docm',
      'a.odt',
      'a.odp',
      'a.ods',
      'a.rtf',
      'A.PPTX',
      'a.xlsx',
    ]) {
      expect(PreviewsService.supportsProperties(name), isTrue, reason: name);
    }
    for (final name in ['a.ppt', 'a.xls', 'a.md', 'a.pdf', 'a.txt', 'notes']) {
      expect(PreviewsService.supportsProperties(name), isFalse, reason: name);
    }
  });
}
