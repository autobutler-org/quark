import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:tailnet_flutter/tailnet_flutter.dart';

/// A client that answers every request with [status] and [headers].
class _StubClient extends http.BaseClient {
  _StubClient(this.status, this.headers);

  final int status;
  final Map<String, String> headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(const <int>[]),
        status,
        headers: headers,
        request: request,
      );
}

class _TestService with AuthenticatedService {
  _TestService(this._client);

  final http.Client _client;

  @override
  http.Client get httpClient => _client;
}

/// The remote-access proxy answers 502 or 504 with [tunnelUnavailableHeader]
/// when the Quark never answered over the tunnel (#3884). The app must read
/// that as the Quark being unreachable, not as an error the Quark sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final uri = Uri.parse('http://127.0.0.1:4100/api/v0/files');
  final down = {tunnelUnavailableHeader: 'timeout'};

  test('every verb throws a connection failure, not a server error', () async {
    final service = _TestService(_StubClient(504, down));
    final calls = <String, Future<Object?> Function()>{
      'get': () => service.authenticatedGet(uri),
      'post': () => service.authenticatedPost(uri),
      'put': () => service.authenticatedPut(uri),
      'patch': () => service.authenticatedPatch(uri),
      'delete': () => service.authenticatedDelete(uri),
      'send': () => service.authenticatedSend(http.Request('GET', uri)),
      'download': () => service.authenticatedDownload(uri),
    };
    for (final MapEntry(key: verb, value: call) in calls.entries) {
      Object? caught;
      try {
        await call();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<RemoteAccessUnavailableException>(), reason: verb);
      expect(isQuarkUnreachableError(caught!), isTrue, reason: verb);
      expect(
        Errors.message(caught, 'load your files'),
        quarkDisconnectedInline,
        reason: verb,
      );
    }
  });

  test("the Quark's own 502 is still the Quark's answer", () async {
    final service = _TestService(_StubClient(502, const {}));
    final response = await service.authenticatedGet(uri);
    expect(response.statusCode, 502);
  });
}
