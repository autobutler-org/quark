import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/embedded_tunnel_io.dart';

/// One bridge call, as the fake recorded it.
typedef _Call = ({String op, String stateDir, String authKey, String upstream});

/// Behaves like the Go bridge: one node per process, a second start refused
/// while it runs, and a start with a key leaving state on disk.
class _FakeBridge implements TunnelBridge {
  final calls = <_Call>[];
  var running = false;
  var stopIgnored = false;
  var _nextPort = 40000;

  List<_Call> get starts => [
    for (final call in calls)
      if (call.op == 'start') call,
  ];

  @override
  Future<TunnelStart> start({
    required String stateDir,
    required String controlUrl,
    required String authKey,
    required String hostname,
    required String upstream,
  }) async {
    calls.add((
      op: 'start',
      stateDir: stateDir,
      authKey: authKey,
      upstream: upstream,
    ));
    if (running) {
      return (port: -1, error: '', token: '', alreadyRunning: true);
    }
    if (authKey.isNotEmpty) {
      final state = Directory(stateDir);
      await state.create(recursive: true);
      await File('${state.path}/login').writeAsString(authKey);
    }
    running = true;
    return (port: ++_nextPort, error: '', token: 't', alreadyRunning: false);
  }

  @override
  Future<void> stop() async {
    calls.add((op: 'stop', stateDir: '', authKey: '', upstream: ''));
    if (!stopIgnored) running = false;
  }

  @override
  Future<Map<String, dynamic>> status() async => {
    'state': running ? 'Running' : 'Stopped',
  };
}

const _quarkA = 'http://100.64.0.1:80';
const _quarkB = 'http://100.64.0.2:80';
const _control = 'https://headscale.example';

void main() {
  late Directory root;
  late _FakeBridge bridge;
  late TunnelNode node;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tunnel_node_test');
    bridge = _FakeBridge();
    node = TunnelNode(bridge: bridge, rootDir: () async => root);
  });

  tearDown(() => root.delete(recursive: true));

  test('a second Quark enrolls with its own key after the first stops '
      '(#3784)', () async {
    await node.enroll(
      controlUrl: _control,
      authKey: 'key-a',
      upstream: _quarkA,
    );
    final stateA = bridge.starts.single.stateDir;

    // Switching to B, which has no pairing yet: A's node does not keep
    // answering for it.
    await node.warm(_quarkB);
    expect(bridge.running, isFalse);
    expect(bridge.calls.last.op, 'stop');

    bridge.calls.clear();
    await node.enroll(
      controlUrl: _control,
      authKey: 'key-b',
      upstream: _quarkB,
    );
    final start = bridge.starts.single;
    expect(start.authKey, 'key-b');
    expect(start.upstream, _quarkB);
    expect(start.stateDir, isNot(stateA));
    expect(await node.proxyUrl(_quarkB), 'http://127.0.0.1:${node.port}');

    // Switching back restarts the node from A's own state, for A.
    bridge.calls.clear();
    await node.warm(_quarkA);
    expect(bridge.calls.map((c) => c.op), ['stop', 'start']);
    expect(bridge.calls.last.stateDir, stateA);
    expect(bridge.calls.last.authKey, isEmpty);
    expect(bridge.calls.last.upstream, _quarkA);
    expect(await File('$stateA/login').readAsString(), 'key-a');
  });

  test('enrolling while another Quark runs stops it before the new key '
      'starts', () async {
    await node.enroll(
      controlUrl: _control,
      authKey: 'key-a',
      upstream: _quarkA,
    );
    bridge.calls.clear();

    await node.enroll(
      controlUrl: _control,
      authKey: 'key-b',
      upstream: _quarkB,
    );

    expect(bridge.calls.map((c) => c.op), ['stop', 'start']);
    expect(bridge.calls.last.authKey, 'key-b');
    expect(bridge.running, isTrue);
  });

  test('enrolling again resets that Quark\'s old state', () async {
    await node.enroll(
      controlUrl: _control,
      authKey: 'key-a',
      upstream: _quarkA,
    );
    final state = Directory(bridge.starts.single.stateDir);
    await File('${state.path}/stale').writeAsString('old login');

    await node.enroll(
      controlUrl: _control,
      authKey: 'key-a2',
      upstream: _quarkA,
    );

    expect(await File('${state.path}/stale').exists(), isFalse);
    expect(await File('${state.path}/login').readAsString(), 'key-a2');
  });

  test('a node already running is never taken as this enrollment', () async {
    // A node this lifecycle did not start, possibly another Quark's.
    bridge.running = true;
    bridge.stopIgnored = true;

    await expectLater(
      node.enroll(controlUrl: _control, authKey: 'key-b', upstream: _quarkB),
      throwsException,
    );
    expect(node.port, 0);
    expect(await node.proxyUrl(_quarkB), isNull);
  });

  test('a stray node is stopped and the start retried once', () async {
    await node.enroll(
      controlUrl: _control,
      authKey: 'key-a',
      upstream: _quarkA,
    );
    await node.warm('');
    // A node this lifecycle does not know about, possibly another Quark's.
    bridge.running = true;
    bridge.calls.clear();

    await node.warm(_quarkA);

    expect(bridge.calls.map((c) => c.op), ['start', 'stop', 'start']);
    expect(node.port, greaterThan(0));
  });

  test('a Quark with no state does not start the node', () async {
    expect(await node.proxyUrl(_quarkA), isNull);
    await node.warm(_quarkA);
    expect(bridge.starts, isEmpty);
  });

  test('the shared state from earlier builds moves to its Quark', () async {
    await Directory('${root.path}/state').create();
    await File('${root.path}/state/login').writeAsString('key-a');
    await File('${root.path}/tunnel.json').writeAsString(
      jsonEncode({
        'controlUrl': _control,
        'hostname': 'phone-0001',
        'upstream': _quarkA,
      }),
    );

    expect(await node.proxyUrl(_quarkA), 'http://127.0.0.1:${node.port}');

    final start = bridge.starts.single;
    expect(start.upstream, _quarkA);
    expect(start.authKey, isEmpty);
    expect(await File('${start.stateDir}/login').readAsString(), 'key-a');
    expect(await File('${root.path}/tunnel.json').exists(), isFalse);
    expect(await Directory('${root.path}/state').exists(), isFalse);

    // Quark B never inherits A's login.
    expect(await node.proxyUrl(_quarkB), isNull);
  });
}
