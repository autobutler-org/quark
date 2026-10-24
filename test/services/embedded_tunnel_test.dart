import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/embedded_tunnel.dart';
import 'package:quark/services/embedded_tunnel_stub.dart';

/// The web stand-in, and the JSON the bridge returns.
void main() {
  test('the stub never starts a node', () async {
    expect(tunnelIsSupported, isFalse);
    expect(await tunnelProxyUrl('http://100.64.0.1'), isNull);
    await tunnelWarm('http://100.64.0.1');
    await tunnelWarm('');
    tunnelWatch(() => fail('the stub does not watch the app lifecycle'));
    expect(await tunnelStatusJson(), {
      'state': 'Stopped',
      'tailnetIPs': <String>[],
      'port': 0,
      'error': '',
    });
  });

  test('parses a running bridge', () {
    final status = TunnelStatus.fromJson({
      'state': 'Running',
      'tailnetIPs': ['100.64.0.8'],
      'port': 43210,
      'error': '',
    });
    expect(status.state, 'Running');
    expect(status.tailnetIPs, ['100.64.0.8']);
    expect(status.port, 43210);
    expect(status.error, isEmpty);
  });

  test('parses a stopped bridge and a failure', () {
    final stopped = TunnelStatus.fromJson(const {});
    expect(stopped.state, 'Stopped');
    expect(stopped.tailnetIPs, isEmpty);
    expect(stopped.port, 0);

    final failed = TunnelStatus.fromJson({
      'state': 'NeedsLogin',
      'port': 9,
      'error': 'the tailnet rejected the auth key',
    });
    expect(failed.state, 'NeedsLogin');
    expect(failed.error, 'the tailnet rejected the auth key');
  });

  test('the public status on a host without the bridge is stopped', () async {
    expect(EmbeddedTunnel.isSupported, isFalse);
    final status = await EmbeddedTunnel.status();
    expect(status.state, 'Stopped');
    expect(await EmbeddedTunnel.proxyUrl('http://100.64.0.1'), isNull);
  });
}
