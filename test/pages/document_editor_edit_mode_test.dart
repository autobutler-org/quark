import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1568: a freshly created doc opened read-only, so the user had to tap Edit
/// before typing into an empty page. Opening an existing doc stays read-only
/// (#939).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpEditor(WidgetTester tester, DocumentEditorPage page) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => page)],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('an existing doc opens read-only', (tester) async {
    await pumpEditor(tester, const DocumentEditorPage(filePath: 'q1.qdoc'));

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('a just-created doc opens in edit mode', (tester) async {
    await pumpEditor(
      tester,
      const DocumentEditorPage(filePath: 'q1.qdoc', startInEditMode: true),
    );

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });
}
