import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';

import '../services/events_service_test.dart' show FakeChannel;

/// Runs [EventsService] over fake sockets, so a test can drop the connection
/// and watch what a page does when it comes back.
class ReconnectingEvents {
  final _channels = <FakeChannel>[];

  /// Starts the service against a fake Quark. Call from a `testWidgets` body.
  Future<void> start() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    EventsService.connectChannel = (uri, {headers}) {
      final channel = FakeChannel();
      _channels.add(channel);
      return channel;
    };
    await AppSettings.instance.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await AppSettings.instance.setSessionToken('a-token');
    EventsService.instance.start();
  }

  /// Closes the socket and waits out the backoff until the service is back.
  Future<void> reconnect(WidgetTester tester) async {
    _channels.last.closeFromServer();
    await tester.pump(const Duration(seconds: 2));
  }

  /// Stops the service and puts the settings back as [start] found them.
  Future<void> stop() async {
    EventsService.instance.stop();
    await AppSettings.instance.setSessionToken(null);
    while (AppSettings.instance.hosts.isNotEmpty) {
      await AppSettings.instance.removeHost(
        AppSettings.instance.hosts.length - 1,
      );
    }
  }
}
