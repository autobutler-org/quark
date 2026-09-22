import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1745: the editor manages its tabs through the strip under the grid, and
/// every change goes out through the autosave.
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
    final sheet = jsonEncode({
      'tabs': [
        {'name': 'Sheet 1', 'data': <String, Object>{}},
        {'name': 'Budget', 'data': <String, Object>{}},
      ],
    });
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.method == 'GET') return http.Response(sheet, 200);
      return http.Response('{}', 200);
    });
    resetSharedHttpClient();
  });

  tearDown(() async {
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    await AppSettings.instance.setSessionToken(null);
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: SpreadsheetEditorPage(filePath: 'budget.qsheet')),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the menu on the tab at [index] and chooses [action].
  Future<void> chooseFromMenu(
    WidgetTester tester,
    int index,
    String action,
  ) async {
    await tester.longPress(find.byKey(ValueKey('sheet_tab_$index')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('sheet_tab_menu_$action')));
    await tester.pumpAndSettle();
  }

  /// The change is waiting on the autosave: the save icon shows unsaved
  /// work. The timer is then let fire so none is left pending.
  Future<void> expectPendingSave(WidgetTester tester) async {
    expect(find.byIcon(QuarkIcons.save), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('add appends Sheet (highest N + 1) and selects it', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('sheet_tab_add')));
    await tester.pumpAndSettle();

    expect(find.text('Sheet 2'), findsOneWidget);
    expect(
      tester.widget<SheetTabStrip>(find.byType(SheetTabStrip)).selectedIndex,
      2,
    );
    await expectPendingSave(tester);
  });

  testWidgets('rename refuses a name another tab has, in any case', (
    tester,
  ) async {
    await pumpEditor(tester);

    await chooseFromMenu(tester, 0, 'rename');
    final nameField = find.descendant(
      of: find.byType(QuarkNameDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField, 'BUDGET');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text(Errors.sheetNameTaken), findsOneWidget);
    expect(find.byType(QuarkNameDialog), findsOneWidget);

    await tester.enterText(nameField, 'Totals');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(QuarkNameDialog), findsNothing);
    expect(find.text('Totals'), findsOneWidget);
    await expectPendingSave(tester);
  });

  testWidgets('delete asks first, then removes the tab', (tester) async {
    await pumpEditor(tester);

    await chooseFromMenu(tester, 1, 'delete');
    await tester.tap(find.byKey(const ValueKey('delete_sheet_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Budget'), findsNothing);
    expect(find.byKey(const ValueKey('sheet_tab_1')), findsNothing);
    await expectPendingSave(tester);
  });
}
