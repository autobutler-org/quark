import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #4110: leaving a sheet inside the auto-save window dropped the edit with
/// no word. It asks now, and auto-save holds while it does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every upload the editor sent.
  late int uploads;

  setUp(() {
    uploads = 0;
    SharedPreferences.setMockInitialValues({});
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.method == 'POST') {
        uploads++;
        return http.Response('{"files":[]}', 200);
      }
      return http.Response('', 200);
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Opens a sheet at its own URL, so its back button is the editor's own
  /// [BackButton], and makes an edit by adding a tab.
  Future<void> pumpEditedSheet(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const SpreadsheetEditorPage(filePath: 's.qsheet'),
        ),
        GoRoute(path: '/files', builder: (_, _) => const Text('files')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet_tab_add')));
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    // Short of the auto-save delay: long enough for the dialog to open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('leaving an unsaved sheet asks, and auto-save waits', (
    tester,
  ) async {
    await pumpEditedSheet(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(uploads, 0);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(uploads, 0);
    expect(find.text('files'), findsOneWidget);
  });

  testWidgets('cancel stays, and auto-save resumes', (tester) async {
    await pumpEditedSheet(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(uploads, 0);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    expect(find.text('files'), findsNothing);
  });
}
