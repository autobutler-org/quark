import 'dart:convert';
import 'dart:io';

import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart' show CellFormat;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2691: column widths, row heights and frozen panes live in the `.qsheet`
/// tab beside its data, and sheets saved before them still open. #2694: so do
/// column filters. #2693: and cell formats.
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

  final rows = {
    'rows': [
      ['Item', 'Cost'],
      ['Rent', '1200'],
      ['Food', '400'],
    ],
  };

  Future<void> pumpEditor(
    WidgetTester tester,
    Map<String, Object> tab, {
    Size size = const Size(1280, 800),
  }) async {
    final sheet = jsonEncode({
      'tabs': [tab],
    });
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path.endsWith('/download')) {
        return http.Response(sheet, 200);
      }
      return http.Response('{}', 200);
    });
    resetSharedHttpClient();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: SpreadsheetEditorPage(filePath: 'budget.qsheet')),
    );
    await tester.pumpAndSettle();
  }

  DataSheetController sheetController(WidgetTester tester) =>
      tester.widget<DataSheet>(find.byType(DataSheet)).controller!;

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('a sheet saved before sizes and freeze opens ($name)', (
      tester,
    ) async {
      await pumpEditor(tester, {'name': 'Sheet 1', 'data': rows}, size: size);

      expect(find.text('Rent'), findsOneWidget);
      final controller = sheetController(tester);
      expect(controller.columnWidths, [100.0, 100.0]);
      expect(controller.rowHeights, [40.0, 40.0, 40.0]);
      expect(controller.frozenRows, 0);
      expect(controller.hasFilters, isFalse);
      expect(controller.formats, isEmpty);
      expect(find.byKey(const ValueKey('frozen_rows_divider')), findsNothing);
    });

    testWidgets('saved cell formats are drawn ($name)', (tester) async {
      await pumpEditor(tester, {
        'name': 'Sheet 1',
        'data': rows,
        'formats': [
          {'row': 0, 'col': 0, 'bold': true},
          {'row': 1, 'col': 1, 'numberFormat': 'currency', 'decimals': 0},
        ],
      }, size: size);

      final controller = sheetController(tester);
      expect(controller.formatAt(0, 0).bold, isTrue);
      expect(find.text(r'$1,200'), findsOneWidget);
      expect(controller.cellAt(1, 1).value, '1200');
    });

    testWidgets('saved filters hide their rows ($name)', (tester) async {
      await pumpEditor(tester, {
        'name': 'Sheet 1',
        'data': rows,
        'frozenRows': 1,
        'filters': [
          {
            'column': 0,
            'hidden': ['Food'],
          },
        ],
      }, size: size);

      final controller = sheetController(tester);
      expect(
        controller.filterFor(0),
        const ColumnFilter(hiddenValues: {'Food'}),
      );
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Food'), findsNothing);
      expect(find.byKey(const ValueKey('row_num_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('row_num_2')), findsNothing);
    });

    testWidgets('saved sizes and freeze are applied ($name)', (tester) async {
      await pumpEditor(tester, {
        'name': 'Sheet 1',
        'data': rows,
        'columnWidths': [150, 90],
        'rowHeights': [30, 40, 60],
        'frozenRows': 1,
        'frozenColumns': 1,
      }, size: size);

      final controller = sheetController(tester);
      expect(controller.frozenRows, 1);
      expect(controller.frozenColumns, 1);
      expect(
        tester.getSize(find.byKey(const ValueKey('r0c0'))),
        const Size(150, 30),
      );
      expect(find.byKey(const ValueKey('frozen_rows_divider')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('frozen_columns_divider')),
        findsOneWidget,
      );
    });
  }

  testWidgets('a sheet with flex-era widths of the wrong length opens', (
    tester,
  ) async {
    await pumpEditor(tester, {
      'name': 'Sheet 1',
      'data': rows,
      'columnFlex': [2, 1],
      'rowHeights': [30],
    });

    final controller = sheetController(tester);
    expect(controller.columnWidths, [200.0, 100.0]);
    expect(controller.rowHeights, [30.0, 40.0, 40.0]);
  });

  testWidgets('the saved form carries the freeze, filters and formats', (
    tester,
  ) async {
    // The autosave's upload opens its own client; refuse it so nothing
    // depends on a live Quark.
    final previous = HttpOverrides.current;
    HttpOverrides.global = _RefuseHttp();
    addTearDown(() => HttpOverrides.global = previous);
    await pumpEditor(tester, {'name': 'Sheet 1', 'data': rows});

    sheetController(tester)
      ..applyFormat(
        const CellRange(top: 0, left: 0, bottom: 0, right: 1),
        (f) => f.withBold(true).withFillColor(0x4010B981),
      )
      ..setFrozenRows(1)
      ..setColumnWidth(1, 175)
      ..setColumnFilter(
        1,
        const ColumnFilter(
          condition: FilterCondition(FilterConditionKind.lessThan, '1000'),
        ),
      );
    await tester.pump();

    // Duplicating a tab round-trips it through the form it is saved in.
    await tester.longPress(find.byKey(const ValueKey('sheet_tab_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet_tab_menu_duplicate')));
    await tester.pumpAndSettle();

    final copy = sheetController(tester);
    expect(copy.frozenRows, 1);
    expect(copy.columnWidths, [100.0, 175.0]);
    expect(copy.visibleRows, [0, 2]);
    expect(
      copy.formatAt(0, 1),
      const CellFormat(bold: true, fillColor: 0x4010B981),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}

/// Real sockets fail immediately, so the autosave never reaches a network.
class _RefuseHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionFactory = (uri, proxyHost, proxyPort) {
        throw const SocketException('refused');
      };
  }
}
