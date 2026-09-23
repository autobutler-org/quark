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

/// #2250: the trash has had multi-select since it had a restore button, but
/// the only way in was a long press on a row. A mouse does not long-press, so
/// on the web the trash looked like it had no bulk actions at all. The app bar
/// now offers the same entry point a pointer can reach.
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
    await tester.pumpWidget(const MaterialApp(home: TrashPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final select = find.byKey(const ValueKey('trash_select'));
  final emptyTrash = find.byKey(const ValueKey('trash_empty'));

  const trashedNote = <String, Object>{
    'trashName': 'notes.txt.1',
    'name': 'notes.txt',
    'originalPath': 'Docs/notes.txt',
    'isDir': false,
    'size': 12,
    'trashedAt': '2026-09-10T00:00:00Z',
    'expiresAt': '2026-10-10T00:00:00Z',
  };

  testWidgets('the app bar starts a selection', (tester) async {
    serve([trashedNote]);
    await pumpTrash(tester);

    expect(find.byType(FileSelectionBar), findsNothing);
    expect(tester.widget<QuarkBarIconButton>(select).onPressed, isNotNull);

    await tester.tap(select);
    await tester.pump();

    expect(find.byType(FileSelectionBar), findsOneWidget);
  });

  testWidgets('an empty trash has nothing to select', (tester) async {
    await pumpTrash(tester);

    expect(tester.widget<QuarkBarIconButton>(select).onPressed, isNull);
  });

  // #2096: disabled, like select, until the root listing has items.
  testWidgets('empty trash is disabled when there is nothing to clear', (
    tester,
  ) async {
    await pumpTrash(tester);

    expect(tester.widget<QuarkBarIconButton>(emptyTrash).onPressed, isNull);
    expect(tester.widget<QuarkBarIconButton>(select).onPressed, isNull);
  });

  testWidgets('empty trash is enabled when the trash has items', (
    tester,
  ) async {
    serve([trashedNote]);
    await pumpTrash(tester);

    expect(emptyTrash, findsOneWidget);
    expect(tester.widget<QuarkBarIconButton>(emptyTrash).onPressed, isNotNull);
  });

  testWidgets('empty trash stays hidden inside a folder', (tester) async {
    serve(
      const [],
      contents: const {
        'items': [
          {'name': 'one.jpg', 'path': 'one.jpg', 'isDir': false, 'size': 12},
        ],
        'originalPath': 'Pictures/album',
        'expiresAt': '2026-10-01T12:00:00Z',
      },
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: TrashPage(location: (serial: '', trashName: 'x_album', path: '')),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(emptyTrash, findsNothing);
    expect(tester.widget<QuarkBarIconButton>(select).onPressed, isNotNull);
  });

  testWidgets('empty trash stays disabled while the listing is loading', (
    tester,
  ) async {
    final gate = Completer<void>();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path.startsWith('/api/v0/storage/devices')) {
        return http.Response(jsonEncode({'devices': <Object>[]}), 200);
      }
      if (request.url.path == '/api/v0/trash') {
        await gate.future;
        return http.Response(
          jsonEncode({
            'retentionDays': 30,
            'items': [trashedNote],
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });
    resetSharedHttpClient();

    await tester.pumpWidget(const MaterialApp(home: TrashPage()));
    await tester.pump();

    expect(tester.widget<QuarkBarIconButton>(emptyTrash).onPressed, isNull);

    gate.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.widget<QuarkBarIconButton>(emptyTrash).onPressed, isNotNull);
  });
}

/// An event socket that never opens and never says anything, so the page
/// loads once and stays put.
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
