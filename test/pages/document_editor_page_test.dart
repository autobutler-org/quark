import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2043: the word count sat at `0 words` while the user typed, and only
/// moved once Save rebuilt the page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? stored;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.method == 'GET' && stored != null) {
        return http.Response(stored!, 200);
      }
      return http.Response('', 200);
    });
  });

  tearDown(() {
    stored = null;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> pumpEditor(WidgetTester tester, DocumentEditorPage page) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => page)],
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

  /// Types [text] at the end of the document the way the platform keyboard
  /// does: one editing-state update from the text input connection.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();
    // Quill's editing value is the plain text, trailing newline included.
    final current = tester.testTextInput.editingState!['text'] as String;
    final body = current.substring(0, current.length - 1);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$body$text\n',
        selection: TextSelection.collapsed(offset: body.length + text.length),
      ),
    );
    await tester.pump();
  }

  testWidgets('the count follows typing in a new doc, before any save', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      const DocumentEditorPage(filePath: 'q1.qdoc', startInEditMode: true),
    );
    expect(find.text('0 words'), findsOneWidget);

    await type(tester, 'hello there world');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('3 words'), findsOneWidget);
    expect(find.text('Unsaved'), findsOneWidget);
  });

  testWidgets('the count follows typing in an existing doc after Edit', (
    tester,
  ) async {
    stored = jsonEncode({
      'ops': [
        {'insert': 'one two\n'},
      ],
    });
    await pumpEditor(tester, const DocumentEditorPage(filePath: 'q1.qdoc'));
    expect(find.text('2 words'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('document_editor_edit')));
    await tester.pumpAndSettle();
    await type(tester, ' three');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('3 words'), findsOneWidget);
  });
}
