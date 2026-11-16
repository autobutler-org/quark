import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/router.dart';
import 'package:quark/widgets/layout/file_route_chrome.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #4105: the chrome the code, Markdown, plaintext and model pages share.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GoRouter> pumpChrome(WidgetTester tester, {bool dirty = false}) async {
    final router = GoRouter(
      initialLocation: '/code/logs/server.log?serial=s1',
      routes: [
        GoRoute(
          path: '${AppRoutes.files}/:path(.*)',
          builder: (_, state) => Scaffold(body: Text('folder:${state.uri}')),
        ),
        GoRoute(
          path: '${AppRoutes.codeViewer}/:path(.*)',
          builder: (_, state) => FileRouteChrome(
            filePath: state.pathParameters['path'] ?? '',
            deviceSerial: state.uri.queryParameters['serial'] ?? '',
            dirty: dirty,
            actions: const [Text('page action', key: ValueKey('action'))],
            body: const Text('body'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('shows the file name, the actions and the body', (tester) async {
    await pumpChrome(tester);

    expect(find.text('server.log'), findsOneWidget);
    expect(find.byKey(const ValueKey('action')), findsOneWidget);
    // The theme is in Settings and the account sheet now (#4150).
    expect(find.byType(AppThemeToggle), findsNothing);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('marks a dirty file in the title', (tester) async {
    await pumpChrome(tester, dirty: true);

    expect(find.text('server.log •'), findsOneWidget);
  });

  testWidgets('Back with nothing to pop leaves for the file\'s folder', (
    tester,
  ) async {
    final router = await pumpChrome(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/files/logs?serial=s1',
    );
  });
}
