import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient(
      (request) async => http.Response.bytes(
        request.url.queryParameters['filePath']!.codeUnits,
        200,
      ),
    );
  });
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  // "Open with" hands the file to another app, which reads it after the call
  // returns: the file has to outlive the call, and carry its own name so the
  // system can pick an app by extension. The next open cleans up the last.
  test('lands the file under its name and keeps only the latest', () async {
    final first = await FilesService.downloadForOpenWith(
      'docs/report.pdf',
      fileName: 'report.pdf',
    );
    expect(first, endsWith('/report.pdf'));
    expect(await File(first).readAsString(), 'docs/report.pdf');

    final second = await FilesService.downloadForOpenWith(
      'docs/notes.txt',
      fileName: 'notes.txt',
    );
    expect(await File(second).readAsString(), 'docs/notes.txt');
    expect(
      File(first).existsSync(),
      isFalse,
      reason: 'the previous open-with file is deleted on the next open',
    );

    await File(second).parent.delete(recursive: true);
  });
}
