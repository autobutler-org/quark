import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';

/// A Quark that answers one canned response, and remembers what it was asked
/// and whether it was closed.
class _FakeClient extends http.BaseClient {
  _FakeClient({
    this.statusCode = 200,
    this.body = '{"setup":true}',
    this.error,
  });

  final int statusCode;
  final String body;
  final Object? error;
  final requested = <Uri>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    if (error != null) throw error!;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      request: request,
    );
  }

  @override
  void close() => closed = true;
}

/// #2032: a host is probed before it is saved. The probe has to reach the
/// address it was handed rather than the active host, has to answer "no"
/// rather than throw, and may not leak the client it built for one request.
void main() {
  late _FakeClient client;

  tearDown(() => hostProbeHttpClientFactory = buildLocalTrustHttpClient);

  void serve(_FakeClient fake) {
    client = fake;
    hostProbeHttpClientFactory = (_) => fake;
  }

  test('probes /auth/status on the address it was given', () async {
    serve(_FakeClient());

    expect(await AuthService.isReachable('http://cabin.local:8080'), isTrue);
    expect(
      client.requested.single.toString(),
      'http://cabin.local:8080/api/v0/auth/status',
    );
  });

  test(
    'a host that refuses the connection is unreachable, not an error',
    () async {
      serve(_FakeClient(error: const SocketExceptionStub()));

      expect(await AuthService.isReachable('http://localhost:8099'), isFalse);
    },
  );

  test('something listening that is not a Quark is unreachable', () async {
    serve(_FakeClient(statusCode: 404, body: 'not found'));

    expect(await AuthService.isReachable('http://printer.local'), isFalse);
  });

  test('a 200 that is not the status body is unreachable', () async {
    serve(_FakeClient(body: '<html>router login</html>'));

    expect(await AuthService.isReachable('http://192.168.1.1'), isFalse);
  });

  test('the probe closes the client it built', () async {
    serve(_FakeClient());

    await AuthService.isReachable('http://cabin.local');
    expect(client.closed, isTrue);
  });

  test('the client is closed even when the probe fails', () async {
    serve(_FakeClient(error: const SocketExceptionStub()));

    await AuthService.isReachable('http://cabin.local');
    expect(client.closed, isTrue);
  });
}

/// Stands in for the platform socket failure, which a unit test cannot raise
/// for real.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
