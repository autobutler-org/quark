import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/api_explorer_service.dart';
import 'package:quark/utils/api_explorer_config.dart';

/// A client that answers from the test rather than the network.
class _StubClient extends http.BaseClient {
  _StubClient(this._respond);

  final http.StreamedResponse Function(http.BaseRequest request) _respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _respond(request);
}

class _TestService extends ApiExplorerService {
  _TestService(this._client);

  final http.Client _client;

  @override
  http.Client get httpClient => _client;
}

/// The explorer's transport (#4077): it builds the URL from the form and
/// never reads more than [ApiExplorerConfig.maxResponseBytes] of a body.
void main() {
  const cap = ApiExplorerConfig.maxResponseBytes;
  final uri = Uri.parse('https://quark.local/api/v0/files/download');

  test('resolves path parameters as one encoded segment each', () {
    expect(
      ApiExplorerService.resolveUri(
        pathTemplate: '/api/v0/albums/{id}/items/{name}',
        pathParameters: {'id': '7', 'name': 'a/b c'},
        queryParameters: {'serial': 'X1', 'empty': ''},
        base: Uri.parse('https://quark.local'),
      ).toString(),
      'https://quark.local/api/v0/albums/7/items/a%2Fb%20c?serial=X1',
    );
  });

  test('sends a JSON body and answers an error status as a response', () async {
    late http.Request sent;
    final service = _TestService(
      _StubClient((request) {
        sent = request as http.Request;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"nope"}')),
          403,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final response = await service.send(
      method: 'POST',
      uri: uri,
      body: '{"name":"x"}',
    );

    expect(sent.method, 'POST');
    expect(sent.headers['content-type'], startsWith('application/json'));
    expect(sent.body, '{"name":"x"}');
    expect(response.statusCode, 403);
    expect(response.body, '{"error":"nope"}');
    expect(response.headers['content-type'], 'application/json');
    expect(response.truncated, isFalse);
  });

  test('stops reading a never-ending stream at the cap', () async {
    var chunksRead = 0;
    var canceled = false;
    final body = StreamController<List<int>>(onCancel: () => canceled = true);
    // A chunk every turn of the event loop, forever, until canceled.
    void push() {
      if (canceled) return;
      chunksRead++;
      body.add(List.filled(1000, 0x61));
      scheduleMicrotask(push);
    }

    body.onListen = push;
    final service = _TestService(
      _StubClient((_) => http.StreamedResponse(body.stream, 200)),
    );

    final response = await service.send(method: 'GET', uri: uri);

    expect(canceled, isTrue, reason: 'the stream must be canceled');
    expect(response.truncated, isTrue);
    expect(response.body.length, cap);
    expect(chunksRead, lessThan(cap ~/ 1000 + 3));
  });

  test('a body at exactly the cap is not truncated', () async {
    final service = _TestService(
      _StubClient(
        (_) => http.StreamedResponse(Stream.value(List.filled(cap, 0x61)), 200),
      ),
    );

    final response = await service.send(method: 'GET', uri: uri);

    expect(response.truncated, isFalse);
    expect(response.body.length, cap);
  });

  // testWidgets runs on a fake clock, so the read time passes in an instant.
  testWidgets('stops reading a quiet open stream at the read time', (
    tester,
  ) async {
    var canceled = false;
    final body = StreamController<List<int>>(onCancel: () => canceled = true);
    final service = _TestService(
      _StubClient((_) => http.StreamedResponse(body.stream, 200)),
    );
    ApiExplorerResponse? response;
    unawaited(service.send(method: 'GET', uri: uri).then((r) => response = r));
    await tester.pump();
    body.add(utf8.encode('event: ping\n\n'));
    await tester.pump(
      ApiExplorerConfig.maxResponseReadTime - const Duration(seconds: 1),
    );
    expect(response, isNull);

    await tester.pump(const Duration(seconds: 1));

    expect(canceled, isTrue);
    expect(response?.truncated, isTrue);
    expect(response?.body, 'event: ping\n\n');
  });

  test('decodes a body cut mid-character leniently', () async {
    final service = _TestService(
      _StubClient(
        (_) => http.StreamedResponse(
          Stream.value([...List.filled(cap - 1, 0x61), 0xC3, 0xA9]),
          200,
        ),
      ),
    );

    final response = await service.send(method: 'GET', uri: uri);

    expect(response.truncated, isTrue);
    expect(response.body, startsWith('a' * (cap - 1)));
  });
}
