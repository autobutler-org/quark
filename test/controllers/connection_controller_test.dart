import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/connection_config.dart';
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

  // A widget test checks for pending timers before tear-down runs, so it
  // disposes the controller itself and passes autoDispose: false.
  ConnectionController build({
    Future<bool> Function(String address)? probe,
    bool autoDispose = true,
    Listenable? hostChanges,
  }) {
    final c = ConnectionController(
      activeHostChanges: hostChanges ?? ChangeNotifier(),
      probe:
          probe ??
          (address) async {
            probed.add(address);
            return answering.contains(address);
          },
      readRemoteAccess: () async => status,
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
  });

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
      final c = build();
      await c.check();
      expect(saved, [(_lan, _remote)]);
    });

    test('clears it once remote access is off', () async {
      answering = {_lan};
      status = const RemoteAccessStatus(enabled: false);
      final c = build();
      await c.check();
      expect(saved, [(_lan, null)]);
    });

    test('keeps it while remote access is on but reconnecting', () async {
      answering = {_lan};
      status = const RemoteAccessStatus(enabled: true);
      final c = build();
      await c.check();
      expect(saved, isEmpty);
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
}
