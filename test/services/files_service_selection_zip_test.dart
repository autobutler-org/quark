import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paths = [
    (serial: '', filePath: 'Trip/a.jpg'),
    (serial: 'usb2', filePath: 'Camera/b.jpg'),
  ];
  const wire = [
    {'serial': '', 'filePath': 'Trip/a.jpg'},
    {'serial': 'usb2', 'filePath': 'Camera/b.jpg'},
  ];

  late List<http.Request> requests;
  late http.Response Function(http.Request request) answer;

  setUp(() {
    requests = [];
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return answer(request);
    });
  });
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  // Native platforms POST the selection as the `paths` form field and stream
  // the zip onto disk (#4195).
  test('posts the selection as a form and streams the zip to disk', () async {
    answer = (_) => http.Response.bytes(
      utf8.encode('zip bytes'),
      200,
      headers: {'content-disposition': 'attachment; filename="selection.zip"'},
    );

    final downloaded = await FilesService.downloadSelectionZip(paths);

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v0/files/download-selection');
    expect(
      request.headers['content-type'],
      startsWith('application/x-www-form-urlencoded'),
    );
    expect(jsonDecode(request.bodyFields['paths']!), wire);
    expect(await File(downloaded.path).readAsString(), 'zip bytes');
    expect(downloaded.headers['content-disposition'], contains('selection'));
    await downloaded.delete();
  });

  test('a refused selection zip throws its status', () async {
    answer = (_) => http.Response('{"error":"busy"}', 503);

    await expectLater(
      FilesService.downloadSelectionZip(paths),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 503),
      ),
    );
  });

  // The web asks for a token bound to the selection, then submits a form.
  test('issues a token for exactly the selection', () async {
    answer = (_) => http.Response(
      jsonEncode({
        'token': 'tok',
        'expiresAt': '2026-11-17T00:00:00Z',
        'selection': 'selection:abc',
      }),
      200,
    );

    final (:token, :selection) =
        await FilesService.createSelectionDownloadToken(paths);

    expect((token, selection), ('tok', 'selection:abc'));
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v0/files/download-selection-token');
    expect(jsonDecode(request.body), {'paths': wire});
  });

  test('a token answer without a selection is an error', () async {
    answer = (_) => http.Response(jsonEncode({'token': 'tok'}), 200);

    await expectLater(
      FilesService.createSelectionDownloadToken(paths),
      throwsException,
    );
  });
}
