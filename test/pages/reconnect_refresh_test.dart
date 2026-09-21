import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/pages/trash_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Events published while the event socket is down never arrive, and the
/// Quark closes an account's socket on purpose when its role or status
/// changes. Files, Trash and Photos reload their listing when the socket comes
/// back, but not when it first opens, since each already loads on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final connectChannelDefault = EventsService.connectChannel;
  final channels = <ControlledChannel>[];
  var requests = 0;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setSessionToken('a-token');
    requests = 0;
    sharedHttpClientFactory = () => MockClient((_) async {
      requests++;
      return http.Response('[]', 200);
    });
    channels.clear();
    EventsService.connectChannel = (uri, {headers}) {
      final channel = ControlledChannel();
      channels.add(channel);
      return channel;
    };
  });

  tearDown(() async {
    EventsService.instance.stop();
    EventsService.connectChannel = connectChannelDefault;
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    await AppSettings.instance.setSessionToken(null);
  });

  final pages = <String, Widget>{
    'Files': const FileBrowserPage(),
    'Trash': const TrashPage(),
    'Photos': const PhotosPage(),
  };

  for (final MapEntry(key: name, value: page) in pages.entries) {
    testWidgets('$name reloads on a reconnect, not on the first connect', (
      tester,
    ) async {
      // Photos keeps a spinner going, so this pumps a few frames rather than
      // waiting for the tree to settle.
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(MaterialApp(home: page));
      await settle();
      expect(channels, hasLength(1));

      // AutoRefreshMixin drops a refresh within a wall-clock second of the
      // last one, so let real time pass before each connection.
      Future<void> pastDebounce() => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );

      await pastDebounce();
      final beforeFirst = requests;
      channels.last.open();
      await settle();
      expect(
        requests,
        beforeFirst,
        reason: 'the first connect reloads nothing',
      );

      channels.last.closeFromServer();
      await tester.pump(const Duration(seconds: 2));
      expect(channels, hasLength(2));
      await pastDebounce();
      final beforeReconnect = requests;
      channels.last.open();
      await settle();
      expect(requests, greaterThan(beforeReconnect));

      await tester.pumpWidget(const SizedBox());
      channels.last.closeFromServer();
      await tester.pump(const Duration(seconds: 4));
      expect(channels, hasLength(3));
      await pastDebounce();
      final afterDispose = requests;
      channels.last.open();
      await settle();
      expect(
        requests,
        afterDispose,
        reason: 'the page stopped listening when it was disposed',
      );

      EventsService.instance.stop();
    });
  }
}

/// A socket that opens when the test says so and closes when the test says
/// the Quark closed it.
class ControlledChannel implements WebSocketChannel {
  final _ready = Completer<void>();
  final _incoming = StreamController<dynamic>();

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _Sink();

  void open() => _ready.complete();

  void closeFromServer() => _incoming.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
