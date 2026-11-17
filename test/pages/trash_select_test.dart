import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/trash_item.dart';
import 'package:quark/pages/trash_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_events_channel.dart';
import '../support/secure_storage.dart';
import '../support/tap_target_guidelines.dart' show narrowViewport;

/// #2250: the trash has had multi-select since it had a restore button, but
/// the only way in was a long press on a row. A mouse does not long-press, so
/// on the web the trash looked like it had no bulk actions at all. The app bar
/// now offers the same entry point a pointer can reach.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final connectChannelDefault = EventsService.connectChannel;

  setUpAll(mockSecureStorage);

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
    EventsService.connectChannel = (uri, {headers}) =>
        FakeChannel(opened: false);
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
    expect(tester.widget<QuarkBarIconButton>(emptyTrash).onPressed, isNotNull);

    await tester.tap(select);
    await tester.pump();

    expect(find.byType(FileSelectionBar), findsOneWidget);
  });

  // #2096: disabled, like select, until the root listing has items.
  testWidgets('empty trash is disabled when there is nothing to clear', (
    tester,
  ) async {
    await pumpTrash(tester);

    expect(tester.widget<QuarkBarIconButton>(emptyTrash).onPressed, isNull);
    expect(tester.widget<QuarkBarIconButton>(select).onPressed, isNull);
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

  // #4233: on a phone the bar is brand, Select and account; emptying the
  // whole trash is a labeled button under the list, never a bar icon.
  group('on a phone', () {
    Future<void> pumpPhone(WidgetTester tester, {TrashLocation? at}) async {
      tester.view.physicalSize = narrowViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: TrashPage(location: at)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final inBar = find.descendant(
      of: find.byType(QuarkAppBar),
      matching: emptyTrash,
    );
    final button = find.byType(QuarkDangerButton);
    final note = find.byType(QuarkInfoNote);

    testWidgets('empties from a button under the list, not the bar', (
      tester,
    ) async {
      serve([trashedNote]);
      await pumpPhone(tester);

      expect(inBar, findsNothing);
      expect(select, findsOneWidget);
      expect(button, findsOneWidget);
      expect(note, findsOneWidget);
      expect(
        find.text(
          'Items here are deleted for good after 30 days. Restore puts each '
          'one back in the folder it came from.',
        ),
        findsOneWidget,
      );
      // The phone row: name over its subtitle, no Device or Size column.
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('Size'), findsNothing);
      expect(find.text('Device'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Empty trash?'), findsOneWidget);
    });

    testWidgets('hides the button and the note when the trash is empty', (
      tester,
    ) async {
      await pumpPhone(tester);

      expect(find.text('Trash is empty'), findsOneWidget);
      expect(button, findsNothing);
      expect(note, findsNothing);
      expect(emptyTrash, findsNothing);
    });

    testWidgets('hides the button inside a folder', (tester) async {
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
      await pumpPhone(tester, at: (serial: '', trashName: 'x_album', path: ''));

      expect(find.text('one.jpg'), findsOneWidget);
      expect(button, findsNothing);
    });
  });
}
