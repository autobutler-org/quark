import 'package:flutter_test/flutter_test.dart';
import 'package:tailnet_flutter/services/embedded_tunnel.dart';
import 'package:tailnet_flutter/services/embedded_tunnel_stub.dart';
import 'package:tailnet_flutter/services/tunnel_path_log.dart';

/// The debug path log (#3883): each path change and request is logged once.
void main() {
  Map<String, dynamic> status({
    List<Map<String, dynamic>> changes = const [],
    List<Map<String, dynamic>> requests = const [],
  }) => {
    'state': 'Running',
    'quark': {'path': 'relay', 'relayRegion': 'nyc'},
    'pathChanges': changes,
    'requests': requests,
  };

  test('logs each path change and request once, in order', () {
    final log = TunnelPathLog();
    final relay = {'at': '2026-11-16T09:00:00Z', 'path': 'relay (nyc)'};
    final direct = {'at': '2026-11-16T09:00:05Z', 'path': 'direct (internet)'};
    final listing = {
      'at': '2026-11-16T09:00:01Z',
      'route': 'files',
      'status': 200,
      'headersMs': 120.5,
      'bodyMs': 340.25,
      'bytes': 12345,
    };

    expect(log.lines(status(changes: [relay], requests: [listing])), [
      'path: relay (nyc) at 2026-11-16T09:00:00.000Z',
      'request files 200: headers 120.5 ms, body 340.25 ms, 12345 bytes',
    ]);
    expect(log.lines(status(changes: [relay], requests: [listing])), isEmpty);
    expect(log.lines(status(changes: [relay, direct], requests: [listing])), [
      'path: direct (internet) at 2026-11-16T09:00:05.000Z',
    ]);

    log.reset();
    expect(log.lines(status(changes: [relay])), hasLength(1));
  });

  test('ignores entries it cannot read', () {
    final log = TunnelPathLog();
    expect(log.lines({'pathChanges': 'nope', 'requests': null}), isEmpty);
    expect(
      log.lines(
        status(
          changes: [
            {'path': 'relay'},
          ],
        ),
      ),
      isEmpty,
    );
  });

  test('the stub and an unsupported host report no path', () async {
    expect((await tunnelPeerStatusJson())['quark'], isNull);
    expect((await tunnelPingJson(3))['tunnel'], isNull);
    expect((await EmbeddedTunnel.peerStatus())['state'], 'Stopped');
    expect(((await EmbeddedTunnel.ping())['tcp'] as Map)['sent'], 0);
  });
}
