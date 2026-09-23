import 'dart:convert';
import 'dart:io';

import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart' show DataCell;
import 'package:flutter/material.dart' hide DataCell;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/router.dart';
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
      // The editor downloads the sheet and, to rename it, lists its folder.
      if (request.url.path.endsWith('/download')) {
        return http.Response(sheet, 200);
      }
      if (request.method == 'GET') return http.Response('[]', 200);
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

  String location(GoRouter router) =>
      router.routeInformationProvider.value.uri.toString();

  Future<GoRouter> pumpRoutedEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.sheetFile('reports/budget.qsheet'),
      routes: [
        GoRoute(
          path: '${AppRoutes.sheets}/:path(.*)',
          builder: (_, state) => SpreadsheetEditorPage(
            filePath: state.pathParameters['path'] ?? '',
            deviceSerial: state.uri.queryParameters['serial'] ?? '',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('the title offers rename, and cancel leaves the sheet', (
    tester,
  ) async {
    final router = await pumpRoutedEditor(tester);

    expect(find.byKey(const ValueKey('sheet_rename_title')), findsOneWidget);
    expect(find.byTooltip('Rename'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sheet_rename_title')));
    await tester.pumpAndSettle();
    expect(find.text('Rename spreadsheet'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Rename spreadsheet'), findsNothing);
    expect(location(router), AppRoutes.sheetFile('reports/budget.qsheet'));
    expect(find.text('budget.qsheet'), findsOneWidget);
  });

  testWidgets('renaming the title follows the new name', (tester) async {
    final router = await pumpRoutedEditor(tester);

    await tester.tap(find.byKey(const ValueKey('sheet_rename_title')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'forecast',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(location(router), AppRoutes.sheetFile('reports/forecast.qsheet'));
    expect(find.text('forecast.qsheet'), findsOneWidget);
    expect(find.text('budget.qsheet'), findsNothing);
  });

  testWidgets('a failed save does not rename', (tester) async {
    final router = await pumpRoutedEditor(tester);
    // The save upload opens its own client, so the mock never sees it. Refuse
    // that connection instead of hoping nothing is listening on the port.
    final previous = HttpOverrides.current;
    HttpOverrides.global = _RefuseHttp();
    addTearDown(() => HttpOverrides.global = previous);

    tester
        .widget<DataSheet>(find.byType(DataSheet))
        .controller!
        .updateCell(0, 0, DataCell('x'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('sheet_rename_title')));
    await tester.pumpAndSettle();

    expect(find.text('Rename spreadsheet'), findsNothing);
    expect(
      find.text(
        Errors.message(http.ClientException('refused'), 'save the sheet'),
      ),
      findsOneWidget,
    );
    expect(location(router), AppRoutes.sheetFile('reports/budget.qsheet'));
  });
}

/// Real sockets fail immediately. The editor's upload does not use the shared
/// test client, so this is what makes a save fail without a live Quark.
class _RefuseHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionFactory = (uri, proxyHost, proxyPort) {
        throw const SocketException('refused');
      };
  }
}
