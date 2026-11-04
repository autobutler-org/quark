import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailnet_flutter/services/tunnel_token_client.dart';

void main() {
  late HttpServer server;
  late List<String?> seen;

  setUp(() async {
    seen = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seen.add(request.headers.value(tunnelTokenHeader));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Future<void> send(HttpClient client, Uri uri) async {
    final response = await (await client.getUrl(uri)).close();
    await response.drain<void>();
  }

  test('sends the token to the proxy port on 127.0.0.1', () async {
    final client = TunnelTokenHttpClient(
      HttpClient(),
      credentials: () => (port: server.port, token: 'secret'),
    );
    addTearDown(client.close);

    await send(client, Uri.parse('http://127.0.0.1:${server.port}/a'));

    expect(seen, ['secret']);
  });

  test('sends no token to another port or host, or when stopped', () async {
    ({int port, String token})? credentials = (
      port: server.port + 1,
      token: 'secret',
    );
    final client = TunnelTokenHttpClient(
      HttpClient(),
      credentials: () => credentials,
    );
    addTearDown(client.close);

    await send(client, Uri.parse('http://127.0.0.1:${server.port}/a'));
    credentials = (port: server.port, token: 'secret');
    await send(client, Uri.parse('http://localhost:${server.port}/a'));
    credentials = null;
    await send(client, Uri.parse('http://127.0.0.1:${server.port}/a'));

    expect(seen, [null, null, null]);
  });
}
