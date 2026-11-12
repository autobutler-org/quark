import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/plaintext_editor_page.dart';
import 'package:quark/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3186: Back from the plaintext editor returns to the viewer it was opened
/// from, the way the other editors honor their `from` (#2896), and falls back
/// to the folder holding the file, on its device, when there is none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GoRouter> pumpEditor(WidgetTester tester, String location) async {
    Widget stub(String name, GoRouterState state) =>
        Scaffold(body: Text('$name:${state.uri}'));
    final router = GoRouter(
      initialLocation: location,
      routes: [
        for (final (name, prefix) in [
          ('folder', AppRoutes.files),
          ('code', AppRoutes.codeViewer),
          ('markdown', AppRoutes.markdownViewer),
        ])
          GoRoute(
            path: '$prefix/:path(.*)',
            builder: (_, state) => stub(name, state),
          ),
        GoRoute(
          path: '${AppRoutes.plaintextEditor}/:path(.*)',
          builder: (_, state) => PlaintextEditorPage(
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

  String location(GoRouter router) =>
      router.routeInformationProvider.value.uri.toString();

  for (final origin in const [
    '/code/logs/server.log',
    '/code/logs/server.log?serial=s1',
    '/markdown/notes/readme.md',
  ]) {
    testWidgets('Back returns to $origin', (tester) async {
      final router = await pumpEditor(
        tester,
        '/edit/logs/server.log?from=${Uri.encodeQueryComponent(origin)}',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(location(router), origin);
    });
  }

  testWidgets('with no origin, Back goes to the folder on the file\'s device', (
    tester,
  ) async {
    final router = await pumpEditor(tester, '/edit/logs/server.log?serial=s1');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(location(router), '/files/logs?serial=s1');
  });
}
