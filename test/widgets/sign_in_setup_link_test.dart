import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/login/sign_in_form.dart';

/// #2030: the sign-in screen always offered "First time here? Set up this
/// Quark", including on a Quark that already has an owner, where it leads to
/// a wizard that will refuse. #1827 put it there because a slow or failed
/// probe used to strand a user on a sign-in form for an unclaimed Quark, so
/// the rule is not "hide it" but "hide it only when the Quark has said it has
/// an owner".
void main() {
  Future<void> pumpForm(WidgetTester tester, {bool? setupComplete}) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final formKey = GlobalKey<FormState>();
    final username = TextEditingController();
    final password = TextEditingController();
    final usernameFocus = FocusNode();
    final passwordFocus = FocusNode();
    addTearDown(username.dispose);
    addTearDown(password.dispose);
    addTearDown(usernameFocus.dispose);
    addTearDown(passwordFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SignInForm(
              formKey: formKey,
              usernameController: username,
              passwordController: password,
              usernameFocus: usernameFocus,
              passwordFocus: passwordFocus,
              obscurePassword: true,
              loading: false,
              disconnected: false,
              error: null,
              managingHosts: false,
              onToggleManagingHosts: () {},
              onHostsChanged: () {},
              onTogglePassword: () {},
              onSubmit: () {},
              onForgotPassword: () {},
              onSetUpQuark: () {},
              setupComplete: setupComplete,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final link = find.byKey(const ValueKey('login_set_up_quark'));

  testWidgets('a claimed Quark does not offer to be set up', (tester) async {
    await pumpForm(tester, setupComplete: true);

    expect(link, findsNothing);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('an unclaimed Quark offers setup', (tester) async {
    await pumpForm(tester, setupComplete: false);

    expect(link, findsOneWidget);
  });

  testWidgets('an unanswered probe keeps the escape hatch', (tester) async {
    // Null is a failed, slow or unreachable probe — the #1827 case.
    await pumpForm(tester);

    expect(link, findsOneWidget);
  });
}
