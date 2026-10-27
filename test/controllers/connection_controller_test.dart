import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark/services/embedded_tunnel.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/connection_config.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/remote_access_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

const _lan = 'https://quark.local';
const _remote = 'http://100.64.0.7:80';

/// The address switching behind #1880, with every probe injected: which
/// address wins, when the app moves back home, the offline backoff, and how
/// the remote address is learned and forgotten.
void main() {
  late HostEntry? host;
  late Set<String> answering;
  late List<String> probed;
  late RemoteAccessStatus? status;
  late List<(String, String?)> saved;
  late Map<String, StoredPairing> pairings;
  late Map<String, StoredPause> pauses;
  late int pairCalls;
  late int statusReads;
  late List<StoredPairing> enrolled;
  late List<String> warmed;
  late bool nodeRejected;
  late Object? pairFailure;
  late DateTime Function() clock;

  const paired = PairedDevice(
    authKey: 'key',
    controlUrl: 'https://control.example',
    quarkAddress: _remote,
  );

  // A widget test checks for pending timers before tear-down runs, so it
  // disposes the controller itself and passes autoDispose: false.
  ConnectionController build({
    Future<bool> Function(String address)? probe,
    bool autoDispose = true,
    Listenable? hostChanges,
    Future<String?> Function(String upstream)? embeddedProxy,
    Future<void> Function(String upstream)? warmEmbeddedTunnel,
    Future<bool> Function()? rejected,
    bool hasDeviceNode = true,
  }) {
    final c = ConnectionController(
      activeHostChanges: hostChanges ?? ChangeNotifier(),
      probe:
          probe ??
          (address) async {
            probed.add(address);
            return answering.contains(address);
          },
      readRemoteAccess: () async {
        statusReads++;
        return status;
      },
      activeHost: () => host,
      saveRemoteAddress: (h, r) async {
        saved.add((h, r));
        final current = host;
        if (current != null && current.hostAddress == h) {
          host = HostEntry(
            name: current.name,
            hostAddress: h,
            remoteAddress: r,
          );
        }
      },
      // The real tunnel is the phone. These tests inject the answer.
      hasDeviceNode: () => hasDeviceNode,
      embeddedProxy: embeddedProxy ?? (_) async => null,
      warmEmbeddedTunnel:
          warmEmbeddedTunnel ?? (upstream) async => warmed.add(upstream),
      watchEmbeddedTunnel: (_) {},
      pairDevice: () async {
        pairCalls++;
        final failure = pairFailure;
        if (failure != null) throw failure;
        return paired;
      },
      readPairing: (h) async => pairings[h],
      savePairing: (h, pairing) async => pairings[h] = pairing,
      clearPairing: (h) async => pairings.remove(h),
      readPause: (h) async => pauses[h],
      savePause: (h, pause) async => pauses[h] = pause,
      clearPause: (h) async => pauses.remove(h),
      enroll:
          ({
            required String controlUrl,
            required String authKey,
            required String upstream,
          }) async {
            enrolled.add(
              StoredPairing(
                authKey: authKey,
                controlUrl: controlUrl,
                quarkAddress: upstream,
              ),
            );
          },
      nodeRejected: rejected ?? () async => nodeRejected,
      now: () => clock(),
    );
    if (autoDispose) addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    host = HostEntry(name: 'Home', hostAddress: _lan, remoteAddress: _remote);
    answering = {};
    probed = [];
    status = null;
    saved = [];
    pairings = {};
    pauses = {};
    pairCalls = 0;
    statusReads = 0;
    enrolled = [];
    warmed = [];
    nodeRejected = false;
    pairFailure = null;
    clock = DateTime.now;
  });

  void connectedAtHome() {
    answering = {_lan};
    status = const RemoteAccessStatus(
      enabled: true,
      connected: true,
      remoteUrl: _remote,
    );
  }

  test('uses the home address when it answers', () async {
    answering = {_lan};
    final c = build();
    await c.check();
    expect(c.mode, ConnectionMode.local);
    expect(c.baseUrl, isNull);
    expect(probed, [_lan]);
  });

  test('falls back to the remote address when home is silent', () async {
    answering = {_remote};
    final c = build();
    await c.check();
    expect(c.mode, ConnectionMode.remote);
    expect(c.baseUrl, _remote);
    expect(probed, [_lan, _remote]);
  });

  test('uses the embedded proxy instead of the tailnet address', () async {
    const proxy = 'http://127.0.0.1:9';
    answering = {proxy};
    String? asked;
    final c = build(
      embeddedProxy: (upstream) async {
        asked = upstream;
        return proxy;
      },
    );
    await c.check();
    expect(asked, _remote);
    expect(c.mode, ConnectionMode.remote);
    expect(c.baseUrl, proxy);
    expect(probed, [_lan, proxy]);
    expect(saved, isEmpty);
  });

  test('is offline when neither address answers', () async {
    final c = build();
    await c.check();
    expect(c.mode, ConnectionMode.offline);
    expect(c.baseUrl, isNull);
  });

  test('is offline without trying a remote address it does not have', () async {
    host = HostEntry(name: 'Home', hostAddress: _lan);
    final c = build();
    await c.check();
    expect(c.mode, ConnectionMode.offline);
    expect(probed, [_lan]);
  });

  test('has no mode with no Quark configured', () async {
    host = null;
    final c = build();
    await c.check();
    expect(c.mode, isNull);
    expect(c.baseUrl, isNull);
  });

  test('a probe that throws counts as silent', () async {
    final c = build(probe: (_) async => throw Exception('refused'));
    await c.check();
    expect(c.mode, ConnectionMode.offline);
  });

  test('never sends a request to another Quark\'s remote address', () async {
    answering = {_remote};
    final c = build();
    await c.check();
    expect(c.baseUrl, _remote);
    host = HostEntry(name: 'Cabin', hostAddress: 'https://cabin.local');
    expect(c.baseUrl, isNull);
  });

  test('a check started later wins over one still probing', () async {
    final slow = Completer<bool>();
    var calls = 0;
    final c = build(
      probe: (address) {
        calls++;
        if (calls == 1) return slow.future;
        return Future.value(address == _lan);
      },
    );
    final first = c.check();
    await c.check();
    expect(c.mode, ConnectionMode.local);
    slow.complete(false);
    await first;
    expect(c.mode, ConnectionMode.local);
  });

  test('checks again when the active Quark changes', () async {
    const cabin = 'https://cabin.local';
    answering = {_lan, cabin};
    final hostChanges = ValueNotifier<String?>(_lan);
    addTearDown(hostChanges.dispose);
    final c = build(hostChanges: hostChanges);
    c.start();
    await pumpEventQueue();
    expect(c.mode, ConnectionMode.local);
    expect(probed, [_lan]);

    answering = {};
    host = HostEntry(name: 'Cabin', hostAddress: cabin);
    hostChanges.value = cabin;
    await pumpEventQueue();
    expect(probed, [_lan, cabin]);
    expect(c.mode, ConnectionMode.offline);
  });

  test('notifies only when the mode changes', () async {
    answering = {_lan};
    final c = build();
    var notified = 0;
    c.addListener(() => notified++);
    await c.check();
    await c.check();
    expect(notified, 1);
  });

  group('remote address', () {
    test('learns it from a connected Quark while home', () async {
      answering = {_lan};
      host = HostEntry(name: 'Home', hostAddress: _lan);
      status = const RemoteAccessStatus(
        enabled: true,
        connected: true,
        remoteUrl: _remote,
      );
      final warmed = <String>[];
      final c = build(
        warmEmbeddedTunnel: (upstream) async => warmed.add(upstream),
      );
      await c.check();
      expect(saved, [(_lan, _remote)]);
      expect(warmed, [_remote]);
    });

    test('clears it once remote access is off', () async {
      answering = {_lan};
      status = const RemoteAccessStatus(enabled: false);
      final warmed = <String>[];
      final c = build(
        warmEmbeddedTunnel: (upstream) async => warmed.add(upstream),
      );
      await c.check();
      expect(saved, [(_lan, null)]);
      expect(warmed, ['']);
    });

    test('keeps it while remote access is on but reconnecting', () async {
      answering = {_lan};
      status = const RemoteAccessStatus(enabled: true);
      final warmed = <String>[];
      final c = build(
        warmEmbeddedTunnel: (upstream) async => warmed.add(upstream),
      );
      await c.check();
      expect(saved, isEmpty);
      expect(warmed, [_remote]);
    });

    test('leaves it alone without a session to ask with', () async {
      answering = {_lan};
      status = null;
      final c = build();
      await c.check();
      expect(saved, isEmpty);
    });

    test('does not save an address that has not changed', () async {
      answering = {_lan};
      status = const RemoteAccessStatus(
        enabled: true,
        connected: true,
        remoteUrl: _remote,
      );
      final c = build();
      await c.check();
      expect(saved, isEmpty);
    });

    test('is not asked for while on the remote address', () async {
      answering = {_remote};
      status = const RemoteAccessStatus(enabled: false);
      final c = build();
      await c.check();
      expect(saved, isEmpty);
    });
  });

  group('rechecks', () {
    testWidgets('moves back home once the home address answers', (
      tester,
    ) async {
      answering = {_remote};
      final c = build(autoDispose: false);
      await c.check();
      expect(c.mode, ConnectionMode.remote);

      answering = {_lan, _remote};
      await tester.pump(
        ConnectionConfig.recheckInterval - const Duration(seconds: 1),
      );
      expect(c.mode, ConnectionMode.remote);
      await tester.pump(const Duration(seconds: 1));
      expect(c.mode, ConnectionMode.local);
      expect(c.baseUrl, isNull);
      c.dispose();
    });

    testWidgets('moves to the remote address after leaving home', (
      tester,
    ) async {
      answering = {_lan, _remote};
      final c = build(autoDispose: false);
      await c.check();
      expect(c.mode, ConnectionMode.local);

      answering = {_remote};
      await tester.pump(ConnectionConfig.recheckInterval);
      expect(c.mode, ConnectionMode.remote);
      expect(c.baseUrl, _remote);
      c.dispose();
    });

    testWidgets('backs off while offline, then recovers', (tester) async {
      final c = build(autoDispose: false);
      await c.check();
      expect(probed, hasLength(2));

      // The first retry waits the initial backoff; the next waits twice it.
      await tester.pump(ConnectionConfig.offlineBackoffInitial);
      expect(probed, hasLength(4));
      await tester.pump(ConnectionConfig.offlineBackoffInitial);
      expect(probed, hasLength(4));
      await tester.pump(ConnectionConfig.offlineBackoffInitial);
      expect(probed, hasLength(6));

      answering = {_lan};
      await tester.pump(ConnectionConfig.offlineBackoffInitial * 4);
      expect(c.mode, ConnectionMode.local);
      c.dispose();
    });

    testWidgets('a probe that never answers times out', (tester) async {
      final c = build(
        autoDispose: false,
        probe: (address) =>
            address == _remote ? Future.value(true) : Completer<bool>().future,
      );
      unawaited(c.check());
      await tester.pump(ConnectionConfig.lanProbeTimeout);
      await tester.pump();
      expect(c.mode, ConnectionMode.remote);
      c.dispose();
    });
  });

  group('automatic pairing', () {
    test('pairs a signed-in phone at home when nothing is stored', () async {
      connectedAtHome();
      host = HostEntry(name: 'Home', hostAddress: _lan);
      final c = build();
      await c.check();
      expect(pairCalls, 1);
      expect(pairings[_lan]?.authKey, 'key');
      expect(pairings[_lan]?.controlUrl, paired.controlUrl);
      expect(pairings[_lan]?.quarkAddress, _remote);
      expect(enrolled, hasLength(1));
      expect(enrolled.single.authKey, 'key');
      expect(warmed, [_remote]);
      expect(c.pairingError, isNull);
    });

    test('does not pair when this phone already has a key', () async {
      connectedAtHome();
      pairings[_lan] = const StoredPairing(
        authKey: 'kept',
        controlUrl: 'https://control.example',
        quarkAddress: _remote,
      );
      final c = build();
      await c.check();
      expect(pairCalls, 0);
      expect(enrolled, isEmpty);
      expect(pairings[_lan]?.authKey, 'kept');
      expect(warmed, [_remote]);
    });

    test('does not pair away from home', () async {
      answering = {_remote};
      status = const RemoteAccessStatus(
        enabled: true,
        connected: true,
        remoteUrl: _remote,
      );
      final c = build();
      await c.check();
      expect(c.mode, ConnectionMode.remote);
      expect(pairCalls, 0);
      expect(pairings, isEmpty);
    });

    test('does not pair when remote access is still connecting', () async {
      answering = {_lan};
      status = const RemoteAccessStatus(enabled: true);
      final c = build();
      await c.check();
      expect(pairCalls, 0);
      expect(warmed, [_remote]);
    });

    test('does not pair without a session', () async {
      answering = {_lan};
      status = null;
      final c = build();
      await c.check();
      expect(pairCalls, 0);
      expect(statusReads, 1);
    });

    test('a 409 waits for the next check and says nothing', () async {
      connectedAtHome();
      pairFailure = const ApiException(409, 'off');
      final c = build();
      await c.check();
      await c.check();
      expect(pairCalls, 2);
      expect(c.pairingError, isNull);
      expect(pairings, isEmpty);
    });

    testWidgets('a 503 retries after the status poll interval', (tester) async {
      connectedAtHome();
      pairFailure = const ApiException(503, 'connecting');
      final c = build(autoDispose: false);
      await c.check();
      expect(pairCalls, 1);
      await tester.pump(
        RemoteAccessConfig.statusPollInterval - const Duration(seconds: 1),
      );
      expect(pairCalls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(pairCalls, 2);
      expect(c.pairingError, isNull);
      c.dispose();
    });

    test('any other failure is shown through Errors', () async {
      connectedAtHome();
      const failure = ApiException(500, 'boom');
      pairFailure = failure;
      final c = build();
      await c.check();
      expect(pairCalls, 1);
      expect(
        c.pairingError,
        Errors.message(failure, 'set up remote access on this phone'),
      );
      expect(pairings, isEmpty);
    });

    test(
      'a rejected node drops the stored key and pairs again once a visit',
      () async {
        connectedAtHome();
        pairings[_lan] = const StoredPairing(
          authKey: 'expired',
          controlUrl: 'https://control.example',
          quarkAddress: _remote,
        );
        nodeRejected = true;
        final c = build();
        await c.check();
        expect(pairCalls, 1);
        expect(pairings[_lan]?.authKey, 'key');
        expect(warmed, ['', _remote]);

        // The new key is refused too: this visit asks for no third.
        await c.check();
        expect(pairCalls, 1);
        expect(pairings.containsKey(_lan), isFalse);

        answering = {_remote};
        nodeRejected = false;
        await c.check();
        expect(c.mode, ConnectionMode.remote);
        expect(pairCalls, 1);

        connectedAtHome();
        await c.check();
        expect(pairCalls, 2);
        expect(pairings[_lan]?.authKey, 'key');
      },
    );

    // The node is only started by the warm after the home check, so a key
    // that stopped working while the app was closed shows up as a failed
    // start, which the bridge reports as NeedsLogin (#3783).
    test('a stored pairing whose start failed to log in is replaced on the '
        'next home check', () async {
      connectedAtHome();
      pairings[_lan] = const StoredPairing(
        authKey: 'expired',
        controlUrl: 'https://control.example',
        quarkAddress: _remote,
      );
      var bridge = const TunnelStatus(state: 'Stopped');
      final c = build(
        warmEmbeddedTunnel: (upstream) async {
          warmed.add(upstream);
          bridge = TunnelStatus(
            state: upstream.isEmpty ? 'Stopped' : 'NeedsLogin',
            error: upstream.isEmpty ? '' : 'joining the tailnet',
          );
        },
        rejected: () async => ConnectionController.isRejected(bridge),
      );
      await c.check();
      expect(warmed, [_remote]);
      expect(pairCalls, 0);
      expect(pairings[_lan]?.authKey, 'expired');

      await c.check();
      expect(pairCalls, 1);
      expect(enrolled.single.authKey, 'key');
      expect(pairings[_lan]?.authKey, 'key');
    });
  });

  group('pause', () {
    for (final choice in DevicePauseChoice.values) {
      test('pausing for ${choice.name} stops only this phone', () async {
        final c = build();
        await c.pause(choice);
        expect(c.remoteAccessPaused, isTrue);
        expect(c.pauseChoice, choice);
        expect(pauses[_lan]?.choice, choice);
        expect(warmed, ['']);
        expect(pairCalls, 0);
        expect(statusReads, 0);
      });
    }

    test('an hour pause stores when it ends', () async {
      final start = DateTime.utc(2026, 1, 1, 12);
      clock = () => start;
      final c = build();
      await c.pause(DevicePauseChoice.hour);
      expect(pauses[_lan]?.until, start.add(const Duration(hours: 1)));
    });

    testWidgets('an hour pause ends on its own', (tester) async {
      final c = build(autoDispose: false);
      await c.pause(DevicePauseChoice.hour);
      expect(c.remoteAccessPaused, isTrue);
      await tester.pump(const Duration(hours: 1));
      expect(c.remoteAccessPaused, isFalse);
      expect(pauses.containsKey(_lan), isFalse);
      c.dispose();
    });

    test('an until-home pause clears once the phone is home again', () async {
      final c = build();
      await c.pause(DevicePauseChoice.untilHome);

      answering = {_lan};
      await c.check();
      expect(c.remoteAccessPaused, isTrue);

      answering = {};
      await c.check();
      expect(c.remoteAccessPaused, isTrue);
      expect(c.mode, ConnectionMode.offline);

      answering = {_lan};
      await c.check();
      expect(c.remoteAccessPaused, isFalse);
      expect(pauses.containsKey(_lan), isFalse);
      expect(c.mode, ConnectionMode.local);
    });

    test('a pause is still there after a restart', () async {
      final c = build(autoDispose: false);
      await c.pause(DevicePauseChoice.untilManual);
      c.dispose();

      final restarted = build(autoDispose: false);
      restarted.start();
      await pumpEventQueue();
      expect(restarted.remoteAccessPaused, isTrue);
      expect(restarted.pauseChoice, DevicePauseChoice.untilManual);
      restarted.dispose();
    });

    test('an hour pause that already ended is dropped on startup', () async {
      var time = DateTime.utc(2026, 1, 1);
      clock = () => time;
      final c = build(autoDispose: false);
      await c.pause(DevicePauseChoice.hour);
      c.dispose();

      time = time.add(const Duration(hours: 1));
      final restarted = build(autoDispose: false);
      restarted.start();
      await pumpEventQueue();
      expect(restarted.remoteAccessPaused, isFalse);
      expect(pauses.containsKey(_lan), isFalse);
      restarted.dispose();
    });
  });

  // #3779: a desktop has no node of its own, so the Quark's private remote
  // address is out of its reach.
  group('without a node on this device', () {
    test('does not probe the remote address away from home', () async {
      final c = build(hasDeviceNode: false);
      await c.check();
      expect(probed, [_lan]);
      expect(c.mode, ConnectionMode.offline);
      expect(c.baseUrl, isNull);
    });

    test('probes the proxy a node of its own hands back', () async {
      const proxy = 'http://127.0.0.1:41234';
      answering = {proxy};
      final c = build(hasDeviceNode: false, embeddedProxy: (_) async => proxy);
      await c.check();
      expect(probed, [_lan, proxy]);
      expect(c.mode, ConnectionMode.remote);
      expect(c.baseUrl, proxy);
    });

    test('does not ask the Quark for a key at home', () async {
      connectedAtHome();
      final c = build(hasDeviceNode: false);
      await c.check();
      expect(c.mode, ConnectionMode.local);
      expect(pairCalls, 0);
      expect(enrolled, isEmpty);
    });

    test('ignores a pause saved earlier', () async {
      pauses[_lan] = const StoredPause(choice: DevicePauseChoice.untilManual);
      final c = build(hasDeviceNode: false);
      c.start();
      await pumpEventQueue();
      expect(c.hasDeviceNode, isFalse);
      expect(c.remoteAccessPaused, isFalse);
    });
  });
}
