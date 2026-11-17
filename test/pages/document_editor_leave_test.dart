import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #4110: auto-save kept running while the editor asked "Leave without
/// saving?", so the edit the dialog asked about saved itself behind it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every upload the editor sent.
  late int uploads;

  /// Holds an upload open until the test completes it, when set.
  Completer<void>? uploadGate;

  setUp(() {
    uploads = 0;
    uploadGate = null;
    SharedPreferences.setMockInitialValues({});
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.method == 'POST') {
        uploads++;
        await uploadGate?.future;
        return http.Response('{"files":[]}', 200);
      }
      return http.Response('', 200);
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Opens a new doc in edit mode at its own URL, so its back button is the
  /// editor's own [BackButton], which leaves through the prompt.
  Future<void> pumpEditor(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const DocumentEditorPage(
            filePath: 'q.qdoc',
            startInEditMode: true,
          ),
        ),
        GoRoute(path: '/files', builder: (_, _) => const Text('files')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$text\n',
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await tester.pump();
  }

  Future<void> tapBack(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    // Short of the auto-save delay: long enough for the dialog to open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('auto-save waits while the leave prompt is open', (tester) async {
    await pumpEditor(tester);
    await type(tester, 'hello');

    await tapBack(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(uploads, 0);
    expect(find.text('Unsaved'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(uploads, 0);
    expect(find.text('files'), findsOneWidget);
  });

  testWidgets('cancel keeps the edit unsaved and auto-save resumes', (
    tester,
  ) async {
    await pumpEditor(tester);
    await type(tester, 'hello');

    await tapBack(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(uploads, 0);
    expect(find.text('Unsaved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    expect(find.text('Unsaved'), findsNothing);
  });

  testWidgets('a save in flight lands before the prompt is asked', (
    tester,
  ) async {
    uploadGate = Completer<void>();
    await pumpEditor(tester);
    await type(tester, 'hello');
    await tester.pump(const Duration(seconds: 3));
    expect(uploads, 1);

    await tapBack(tester);
    expect(find.text('Unsaved changes'), findsNothing);

    uploadGate!.complete();
    await tester.pumpAndSettle();
    // The save left nothing unsaved, so there was nothing to ask about.
    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.text('files'), findsOneWidget);
  });
}
