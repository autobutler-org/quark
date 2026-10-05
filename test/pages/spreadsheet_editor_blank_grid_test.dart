import 'dart:convert';

import 'package:data_table/data_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/sheet_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2779: an empty sheet opens as a blank grid rather than a single cell, and
/// a sheet that already has data keeps the size it was saved with.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

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
  });

  tearDown(() async {
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    await AppSettings.instance.setSessionToken(null);
  });

  /// Opens the editor on a file whose saved bytes are [sheet].
  Future<void> pumpEditor(WidgetTester tester, String sheet) async {
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path.endsWith('/download')) {
        return http.Response(sheet, 200);
      }
      if (request.method == 'GET') return http.Response('[]', 200);
      return http.Response('{}', 200);
    });
    resetSharedHttpClient();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: SpreadsheetEditorPage(filePath: 'budget.qsheet')),
    );
    await tester.pumpAndSettle();
  }

  DataSheetController shownSheet(WidgetTester tester) =>
      tester.widget<DataSheet>(find.byType(DataSheet)).controller!;

  void expectBlankGrid(WidgetTester tester) {
    expect(shownSheet(tester).rowCount, SheetConfig.startingRows);
    expect(shownSheet(tester).colCount, SheetConfig.startingColumns);
  }

  testWidgets('a new spreadsheet opens with a blank grid', (tester) async {
    // The bytes the Sheets page uploads for a new spreadsheet.
    await pumpEditor(
      tester,
      '{"tabs":[{"name":"Sheet 1","data":{"columns":[],"rows":[]}}]}',
    );

    expectBlankGrid(tester);
  });

  testWidgets('an empty file opens with a blank grid', (tester) async {
    await pumpEditor(tester, '');

    expectBlankGrid(tester);
  });

  testWidgets('an added tab opens with a blank grid', (tester) async {
    await pumpEditor(tester, '');

    await tester.tap(find.byKey(const ValueKey('sheet_tab_add')));
    await tester.pumpAndSettle();

    expectBlankGrid(tester);
    // Let the autosave the new tab scheduled go out.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a sheet with data keeps its size', (tester) async {
    await pumpEditor(
      tester,
      jsonEncode({
        'tabs': [
          {
            'name': 'Sheet 1',
            'data': {
              'rows': [
                ['a', 'b', 'c'],
                ['d', 'e', 'f'],
              ],
            },
          },
        ],
      }),
    );

    expect(shownSheet(tester).rowCount, 2);
    expect(shownSheet(tester).colCount, 3);
  });
}
