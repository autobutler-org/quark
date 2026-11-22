import 'dart:convert';

import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #4380: one click on a read-only document drew the caret, but typing only
/// started after a second click.
///
/// The tap switched to edit mode and left the focus to two post-frame
/// callbacks that unfocused and then refocused the editor. On web with the
/// semantics tree on, a tap on the read-only page reaches the app as a
/// semantics tap, so the editor's own gesture never requests focus: focus
/// came only from those callbacks, after the click had finished, and the
/// browser left the hidden text field unattached while Flutter drew a caret.
/// A widget test has no browser, so these pin the Flutter side: the editor is
/// focused before the next frame, and keeps that focus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient(
      (request) async => http.Response(
        jsonEncode({
          'ops': [
            {'insert': 'one two\n'},
          ],
        }),
        200,
      ),
    );
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<FocusNode> pumpReadOnlyDoc(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const DocumentEditorPage(filePath: 'q1.qdoc'),
        ),
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
    expect(find.text('Edit'), findsOneWidget);
    return tester.widget<QuillEditor>(find.byType(QuillEditor)).focusNode;
  }

  /// Records every time [node] loses focus from now on.
  List<String> focusLosses(FocusNode node) {
    final losses = <String>[];
    var had = node.hasFocus;
    void listener() {
      if (had && !node.hasFocus) losses.add('lost focus');
      had = node.hasFocus;
    }

    node.addListener(listener);
    addTearDown(() => node.removeListener(listener));
    return losses;
  }

  testWidgets(
    'a semantics tap on a read-only page focuses the editor at once',
    (tester) async {
      final editorFocus = await pumpReadOnlyDoc(tester);
      final losses = focusLosses(editorFocus);

      // The page's tap, the way the web engine delivers a click on it.
      tester.semantics.tap(
        find.semantics
            .ancestor(
              of: find.semantics.byLabel('one two'),
              matching: find.semantics.byAction(SemanticsAction.tap),
            )
            .first,
      );
      // Let the focus change apply, but draw no frame: the browser only lets
      // the click focus its text field while the click is being handled.
      await tester.idle();

      expect(find.text('Done'), findsNothing, reason: 'no frame drawn yet');
      expect(editorFocus.hasFocus, isTrue);

      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      expect(editorFocus.hasFocus, isTrue);
      expect(losses, isEmpty);
    },
    semanticsEnabled: true,
  );

  testWidgets('a click on a read-only page keeps the editor focused', (
    tester,
  ) async {
    final editorFocus = await pumpReadOnlyDoc(tester);
    final losses = focusLosses(editorFocus);

    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(editorFocus.hasFocus, isTrue);
    expect(losses, isEmpty, reason: 'no unfocus and refocus after the tap');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.setClientArgs?['readOnly'], isFalse);
  });
}
