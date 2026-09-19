import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/login/sign_in_form.dart';

/// Regression coverage for #2020: submitting an empty sign-in form left
/// "Username is required" and "Password is required" on screen while the user
/// filled the fields in, because a `TextFormField` only revalidates when
/// something asks it to and nothing did until the next submit.
void main() {
  late GlobalKey<FormState> formKey;
  late TextEditingController username;
  late TextEditingController password;

  setUp(() {
    formKey = GlobalKey<FormState>();
    username = TextEditingController();
    password = TextEditingController();
  });

  tearDown(() {
    username.dispose();
    password.dispose();
  });

  Future<void> pumpForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final usernameFocus = FocusNode();
    final passwordFocus = FocusNode();
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
              // What the page does: validate, then talk to the Quark.
              onSubmit: () => formKey.currentState!.validate(),
              onForgotPassword: () {},
              onSetUpQuark: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty submit still says what is missing', (tester) async {
    await pumpForm(tester);

    formKey.currentState!.validate();
    await tester.pump();

    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('the error clears as soon as the field has content', (
    tester,
  ) async {
    await pumpForm(tester);

    formKey.currentState!.validate();
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).first, 'ada');
    await tester.pump();

    expect(find.text('Username is required'), findsNothing);
    // The field the user has not reached yet keeps its answer.
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('emptying a field again asks for it again', (tester) async {
    await pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, 'ada');
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.pump();

    expect(find.text('Username is required'), findsOneWidget);
  });

  testWidgets('nothing is demanded before the form has been touched', (
    tester,
  ) async {
    await pumpForm(tester);

    expect(find.text('Username is required'), findsNothing);
    expect(find.text('Password is required'), findsNothing);
  });
}
