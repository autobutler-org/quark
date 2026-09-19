import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';

/// #2029: a successful password reset called `context.go(login)` and nothing
/// else — no toast, no banner, no prefilled username. The most anxious step
/// in the app ended in silence, which reads as "did that work?".
void main() {
  final settings = AppSettings.instance;

  setUp(() async {
    // The page offers the connect form, not a sign-in form, until a Quark is
    // configured — and the sign-in form is what carries the notice.
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://quark.local'),
    );
  });

  tearDown(() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  Future<void> pumpLoginAt(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) {
            final params = state.uri.queryParameters;
            return LoginPage(
              onLoginSuccess: () {},
              initialUsername: params['username'],
              notice: params['reset'] == '1'
                  ? 'Password updated. Sign in with your new password.'
                  : null,
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('a reset says so on the sign-in form', (tester) async {
    await pumpLoginAt(tester, '${AppRoutes.login}?reset=1&username=ada');

    expect(find.byKey(const ValueKey('notice_banner')), findsOneWidget);
    expect(find.textContaining('Password updated'), findsOneWidget);
  });

  testWidgets('the username comes along so it is not typed again', (
    tester,
  ) async {
    await pumpLoginAt(tester, '${AppRoutes.login}?reset=1&username=ada');

    expect(find.widgetWithText(TextFormField, 'ada'), findsOneWidget);
  });

  testWidgets('an ordinary visit says nothing', (tester) async {
    await pumpLoginAt(tester, AppRoutes.login);

    expect(find.byKey(const ValueKey('notice_banner')), findsNothing);
  });
}
