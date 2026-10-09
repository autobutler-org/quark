import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/books_service.dart';
import 'package:quark/utils/error_text.dart';

/// The books API (#1678): `GET /api/v0/books`, read into `FileNode`s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  /// Answers every request with [status] and [body], recording it.
  void answer(int status, Object body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
  }

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('lists the books the Quark found', () async {
    answer(200, [
      {
        'relPath': 'library/sci-fi/Dune.epub',
        'fileName': 'Dune.epub',
        'size': 2048,
        'type': 'epub',
        'mtime': 1767225600,
      },
    ]);

    final book = (await BooksService.list()).single;

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/books');
    expect(book.name, 'Dune.epub');
    expect(book.apiPath, 'library/sci-fi/Dune.epub');
    expect(book.size, 2048);
    expect(book.fileType, 'epub');
    expect(book.isDir, isFalse);
    expect(book.modifiedAt!.toUtc(), DateTime.utc(2026));
  });

  test('a Quark with no books lists none', () async {
    answer(200, const <Object>[]);
    expect(await BooksService.list(), isEmpty);
  });

  test('a refusal throws the status for Errors to read', () async {
    answer(500, {'error': 'error walking directory /data/files'});
    await expectLater(
      BooksService.list(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 500)),
    );
  });
}
