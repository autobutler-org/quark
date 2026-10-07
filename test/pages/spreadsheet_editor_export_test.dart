import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2696: the control bar exports every tab of the spreadsheet as one Excel
/// workbook, built by the Quark from the saved sheet and handed to the save
/// dialog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const fileDialog = MethodChannel('flutter_file_dialog');
  const exportButton = ValueKey('data_sheet_export_xlsx');

  /// Every request the editor made, as `METHOD path`, in order.
  late List<String> requests;

  /// What the export answers with.
  late http.Response Function() exportResponse;

  /// Answers every request, including the uploads that build their own
  /// client.
  late http.Client client;

  /// The name and bytes handed to the save dialog, once it is shown.
  late Completer<(String, List<int>)> saved;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fileDialog, (call) async {
          final args = call.arguments as Map;
          final source = args['sourceFilePath'] as String;
          saved.complete((
            args['fileName'] as String,
            File(source).readAsBytesSync(),
          ));
          return '/saved/${args['fileName']}';
        });

    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setSessionToken('a-token');

    requests = [];
    saved = Completer();
    exportResponse = () => http.Response.bytes([1, 2, 3], 200);
    final sheet = jsonEncode({
      'tabs': [
        {
          'name': 'Sheet 1',
          'data': {
            'rows': [
              ['a'],
            ],
          },
        },
        {'name': 'Budget', 'data': <String, Object>{}},
      ],
    });
    client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/export/xlsx')) {
        expect(request.url.queryParameters['filePath'], 'money/budget.qsheet');
        return exportResponse();
      }
      if (request.url.path.endsWith('/download')) {
        return http.Response(sheet, 200);
      }
      return http.Response('{}', 200);
    });
    sharedHttpClientFactory = () => client;
    resetSharedHttpClient();
  });

  tearDown(() async {
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    await AppSettings.instance.setSessionToken(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(secureStorage, null)
      ..setMockMethodCallHandler(fileDialog, null);
  });

  for (final (label, size) in const [
    ('narrow', Size(360, 640)),
    ('wide', Size(1280, 800)),
  ]) {
    Future<void> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: SpreadsheetEditorPage(filePath: 'money/budget.qsheet'),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Taps the export button, scrolled into view on a phone, and lets the
    /// export run to [until]. The download streams to a temp file, which takes
    /// real I/O, so the tap happens outside the fake clock.
    Future<T?> runExport<T>(
      WidgetTester tester,
      Future<T> Function() until,
    ) async {
      await tester.ensureVisible(find.byKey(exportButton));
      await tester.pumpAndSettle();
      final result = await tester.runAsync(() async {
        // The save before an export uploads through a client of its own.
        await http.runWithClient(
          () => tester.tap(find.byKey(exportButton)),
          () => client,
        );
        return until().timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('saves the workbook under the sheet name ($label)', (
      tester,
    ) async {
      await pumpEditor(tester);

      final (name, bytes) = (await runExport(tester, () => saved.future))!;

      expect(name, 'budget.xlsx');
      expect(bytes, [1, 2, 3]);
      // A clean sheet is exported as it is, with no save first.
      expect(requests, [
        'GET /api/v0/files/download',
        'GET /api/v0/files/export/xlsx',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saves unsaved edits before exporting ($label)', (
      tester,
    ) async {
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('sheet_tab_add')));
      await tester.pumpAndSettle();

      await runExport(tester, () => saved.future);

      final upload = requests.indexWhere((r) => r.startsWith('POST'));
      final export = requests.indexOf('GET /api/v0/files/export/xlsx');
      expect(upload, isNonNegative, reason: '$requests');
      expect(upload, lessThan(export), reason: '$requests');
      // The save went out ahead of the autosave, which is left with nothing.
      await tester.pump(const Duration(seconds: 3));
      expect(requests.where((r) => r.startsWith('POST')), hasLength(1));
    });

    testWidgets('says so when the export fails ($label)', (tester) async {
      exportResponse = () => http.Response('{"error":"boom"}', 500);
      await pumpEditor(tester);

      await runExport(
        tester,
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      expect(
        find.text(Errors.message(ApiException(500, ''), 'export the sheet')),
        findsOneWidget,
      );
      expect(saved.isCompleted, isFalse);
    });
  }
}
