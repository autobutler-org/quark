import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/trash_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../support/text_scale.dart';

/// #2606, #2603, #2605: the trash survives 200% text on a phone and a desktop,
/// and every control on it is labeled and big enough to hit. A listing is the
/// file browser's own rows, which the file browser's tests hold to the same.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final connectChannelDefault = EventsService.connectChannel;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  /// Answers the calls a trash listing makes, with [items] at the trash root.
  /// [contents] is what a folder listing returns, when the page is inside one.
  void serve(List<Map<String, Object>> items, {Map<String, Object>? contents}) {
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path.startsWith('/api/v0/storage/devices')) {
        return http.Response(jsonEncode({'devices': <Object>[]}), 200);
      }
      if (request.url.path == '/api/v0/trash') {
        return http.Response(
          jsonEncode({'retentionDays': 30, 'items': items}),
          200,
        );
      }
      if (request.url.path == '/api/v0/trash/contents' && contents != null) {
        return http.Response(jsonEncode(contents), 200);
      }
      return http.Response('{}', 200);
    });
    resetSharedHttpClient();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setSessionToken('a-token');
    // The device listing is cached across calls, and so across tests.
    StorageService.invalidateDeviceCache();
    EventsService.connectChannel = (uri, {headers}) => _SilentChannel();
    serve([]);
  });

  tearDown(() async {
    EventsService.instance.stop();
    EventsService.connectChannel = connectChannelDefault;
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    await AppSettings.instance.setSessionToken(null);
  });

  Future<void> pumpTrash(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: const TrashPage(),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testLargeText('an empty trash lays out', (tester, _) async {
    await pumpTrash(tester);

    expect(find.text('Trash is empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
  });
}

class _SilentChannel implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();

  @override
  Future<void> get ready => Completer<void>().future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _SilentSink();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SilentSink implements WebSocketSink {
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
