import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

/// #3989: the Files selection bar offers Move, and only leaves selection once
/// every selected item has moved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> moves;

  setUpAll(mockSecureStorage);

  setUp(() async {
    moves = [];
    sharedHttpClientFactory = () => MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/storage/devices/status')) {
        return http.Response(
          jsonEncode({
            'devices': [
              {
                'name': 'Built-in',
                'devicePath': '/dev/Built-in',
                'mountPoint': '/mnt/Built-in',
                'isInternal': true,
                'isEnabled': true,
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'PUT' && path == '/api/v0/files') {
        moves.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 202);
      }
      if (request.method == 'GET' && path == '/api/v0/files') {
        final rootDir = request.url.queryParameters['rootDir'] ?? '';
        final rows = rootDir.isEmpty
            ? [
                {
                  'name': 'a.txt',
                  'isDir': false,
                  'dirPath': 'a.txt',
                  'size': 1,
                },
                {
                  'name': 'b.txt',
                  'isDir': false,
                  'dirPath': 'b.txt',
                  'size': 1,
                },
                {'name': 'Docs', 'isDir': true, 'dirPath': 'Docs', 'size': 0},
              ]
            : <Map<String, Object>>[];
        return http.Response(jsonEncode(rows), 200);
      }
      return http.Response(path.endsWith('/health') ? '{}' : '[]', 200);
    });
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    StorageService.invalidateDeviceCache();
  });

  tearDown(() {
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    setViewport(tester, const Size(1600, 1000));
    await tester.pumpWidget(const MaterialApp(home: FileBrowserPage()));
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 4));

  Finder moveButton() => find.byKey(const ValueKey('file_selection_move'));

  testWidgets('Move is disabled until something is selected', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('file_top_bar_select')));
    await tester.pumpAndSettle();

    expect(moveButton(), findsOneWidget);
    expect(tester.widget<QuarkBarIconButton>(moveButton()).onPressed, isNull);

    await tester.tap(find.text('a.txt'));
    await tester.pump();

    expect(
      tester.widget<QuarkBarIconButton>(moveButton()).onPressed,
      isNotNull,
    );
    await drain(tester);
  });

  testWidgets('cancel leaves the selection as it was', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('file_top_bar_select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.txt').first);
    await tester.pump();
    await tester.tap(find.text('b.txt').first);
    await tester.pump();
    await tester.tap(moveButton());
    await tester.pumpAndSettle();

    expect(find.text('New file name'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    expect(moves, isEmpty);
    await drain(tester);
  });

  testWidgets('confirm moves only the selection and then leaves selection', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('file_top_bar_select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.txt'));
    await tester.pump();
    await tester.tap(moveButton());
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Docs')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Move'));
    await tester.pumpAndSettle();

    expect(moves, [
      {'oldFilePath': '/a.txt', 'newFilePath': '/Docs/a.txt'},
    ]);
    expect(find.text('Moved 1 item.'), findsOneWidget);
    expect(moveButton(), findsNothing);
    expect(find.text('b.txt'), findsWidgets);
    await drain(tester);
  });
}
