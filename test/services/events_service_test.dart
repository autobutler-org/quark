import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The Quark closes an account's event socket, without sending the event,
/// when that account is promoted, demoted, turned off or deleted (#1911). The
/// app has to come back on its own and say it did, so the admin flag is
/// fetched again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  final settings = AppSettings.instance;
  final channels = <FakeChannel>[];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() {
    channels.clear();
    EventsService.connectChannel = (uri, {headers}) {
      final channel = FakeChannel();
      channels.add(channel);
      return channel;
    };
  });

  tearDown(() async {
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
}

/// The default [EventsService.connectChannel], captured before any test
/// replaces it.
final connectLocalTrustWsDefault = EventsService.connectChannel;

/// A socket that opens at once and closes when the test says the Quark closed
/// it.
class FakeChannel implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  WebSocketSink get sink => FakeSink();

  void closeFromServer() => _incoming.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A sink that accepts a close and nothing else.
class FakeSink implements WebSocketSink {
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
