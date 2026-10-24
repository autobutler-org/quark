import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';

import '../support/fake_events_channel.dart';
import '../support/secure_storage.dart';

/// The Quark closes an account's event socket, without sending the event,
/// when that account is promoted, demoted, turned off or deleted (#1911). The
/// app has to come back on its own and say it did, so the admin flag is
/// fetched again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings.instance;
  final channels = <FakeChannel>[];

  setUpAll(mockSecureStorage);

  setUp(() {
    channels.clear();
    EventsService.connectChannel = (uri, {headers}) {
      final channel = FakeChannel();
      channels.add(channel);
      return channel;
    };
  });

  tearDown(() async {
    EventsService.random = Random();
    EventsService.instance.stop();
    EventsService.connectChannel = connectLocalTrustWsDefault;
    await settings.setSessionToken(null);
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  testWidgets('reconnects after the Quark closes the socket, and says so', (
    tester,
  ) async {
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-token');
    final events = EventsService.instance;
    var opened = 0;
    final sub = events.connections.listen((_) => opened++);
    addTearDown(sub.cancel);

    events.start();
    await tester.pump();
    expect(channels, hasLength(1));
    expect(opened, 1);

    channels.single.closeFromServer();
    await tester.pump();
    expect(channels, hasLength(1), reason: 'reconnects after a delay');

    await tester.pump(const Duration(seconds: 2));
    expect(channels, hasLength(2));
    expect(opened, 2);

    events.stop();
  });

  testWidgets('reports reconnects, but not the first connect', (tester) async {
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-token');
    final events = EventsService.instance;
    var reconnected = 0;
    final sub = events.reconnects.listen((_) => reconnected++);
    addTearDown(sub.cancel);

    events.start();
    await tester.pump();
    expect(reconnected, 0);

    channels.single.closeFromServer();
    await tester.pump(const Duration(seconds: 2));
    expect(channels, hasLength(2));
    expect(reconnected, 1);

    events.stop();
    events.start();
    await tester.pump();
    expect(channels, hasLength(3));
    expect(reconnected, 1, reason: 'a fresh start is a first connect again');

    events.stop();
  });

  // #3087: events published while the socket was down are gone, and most
  // listeners follow `events` alone, so a reconnect has to reach them there.
  testWidgets('a reconnect delivers a resync, but the first connect does not', (
    tester,
  ) async {
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-token');
    final events = EventsService.instance;
    final kinds = <String>[];
    final sub = events.events.listen((e) => kinds.add(e.kind));
    addTearDown(sub.cancel);

    events.start();
    await tester.pump();
    expect(kinds, isEmpty);

    channels.single.closeFromServer();
    await tester.pump(const Duration(seconds: 2));
    expect(channels, hasLength(2));
    expect(kinds, ['resync']);

    events.stop();
  });

  // #2763: reconnects had no jitter, so after a restart every app came back,
  // and refreshed, in the same instant.
  group('reconnect delay', () {
    Duration delay(int attempt, double roll) =>
        EventsService.reconnectDelay(attempt, FixedRandom(roll));

    test('doubles from 1 s and stops at 30 s', () {
      expect(
        [for (var a = 0; a < 8; a++) delay(a, 0.5)],
        const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
          Duration(seconds: 16),
          Duration(seconds: 30),
          Duration(seconds: 30),
          Duration(seconds: 30),
        ],
      );
    });

    test('a long outage never overflows the delay', () {
      expect(delay(64, 0.5), const Duration(seconds: 30));
      expect(delay(1000, 0.5), const Duration(seconds: 30));
    });

    test('spreads each delay by half either way', () {
      expect(delay(0, 0), const Duration(milliseconds: 500));
      expect(delay(0, 0.999), const Duration(milliseconds: 1499));
      expect(delay(3, 0), const Duration(seconds: 4));
      expect(delay(5, 0), const Duration(seconds: 15));
      expect(delay(5, 0.999), const Duration(milliseconds: 44970));
    });

    test('two apps that lost the Quark together come back apart', () {
      final random = Random(7);
      final delays = {
        for (var i = 0; i < 20; i++) EventsService.reconnectDelay(0, random),
      };
      expect(delays.length, greaterThan(15));
    });
  });

  testWidgets('backs off until a message arrives, then starts over', (
    tester,
  ) async {
    EventsService.random = FixedRandom(0.5);
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-token');
    final events = EventsService.instance..start();
    await tester.pump();

    // Opening is not enough: a Quark that accepts and drops the socket at
    // once would otherwise be retried every second forever.
    channels.last.closeFromServer();
    await tester.pump(const Duration(milliseconds: 999));
    expect(channels, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(channels, hasLength(2));

    channels.last.closeFromServer();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(channels, hasLength(2));
    await tester.pump(const Duration(milliseconds: 1));
    expect(channels, hasLength(3));

    channels.last.send('{"kind":"upload","path":"a"}');
    await tester.pump();
    channels.last.closeFromServer();
    await tester.pump(const Duration(seconds: 1));
    expect(channels, hasLength(4), reason: 'a message resets the backoff');

    events.stop();
  });

  test('a resync from the Quark changes every listing', () {
    // The Quark sends one when this socket fell behind and lost events (#2753).
    expect(FileEvent.fromJson({'kind': 'resync'}).changesListing, isTrue);
  });
}

/// A [Random] whose every double is [roll].
class FixedRandom implements Random {
  FixedRandom(this.roll);

  final double roll;

  @override
  double nextDouble() => roll;

  @override
  int nextInt(int max) => (roll * max).floor();

  @override
  bool nextBool() => roll >= 0.5;
}
