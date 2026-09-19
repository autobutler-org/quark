import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/setup/setup_form.dart';

/// Regression coverage for #2008: the setup form carried
/// `AutovalidateMode.onUserInteraction` on the `Form` itself, and a Form-level
/// mode validates every field as soon as any one of them is touched. Typing a
/// username therefore printed "Password is required" and "Please confirm your
/// password" under two fields the user had not reached yet — the first-run
/// screen greeting a new owner with two errors they had not earned.
void main() {
  late GlobalKey<FormState> formKey;
  late TextEditingController username;
  late TextEditingController password;
  late TextEditingController confirm;

  setUp(() {
    formKey = GlobalKey<FormState>();
    username = TextEditingController();
    password = TextEditingController();
    confirm = TextEditingController();
  });

  tearDown(() {
    username.dispose();
    password.dispose();
    confirm.dispose();
  });

  Future<void> pumpForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final usernameFocus = FocusNode();
    final passwordFocus = FocusNode();
    final confirmFocus = FocusNode();
    addTearDown(usernameFocus.dispose);
    addTearDown(passwordFocus.dispose);
    addTearDown(confirmFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SetupForm(
              formKey: formKey,
              usernameController: username,
              passwordController: password,
              confirmController: confirm,
              usernameFocus: usernameFocus,
              passwordFocus: passwordFocus,
              confirmFocus: confirmFocus,
              obscurePassword: true,
              obscureConfirm: true,
              loading: false,
              error: null,
              onTogglePassword: () {},
              onToggleConfirm: () {},
              onSubmit: () => formKey.currentState!.validate(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing a username says nothing about the other fields', (
    tester,
  ) async {
    await pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, 'ada');
    await tester.pump();

    expect(find.text('Username is required'), findsNothing);
    expect(find.text('Password is required'), findsNothing);
    expect(find.text('Please confirm your password'), findsNothing);
  });

  testWidgets('a field that has been used speaks for itself', (tester) async {
    await pumpForm(tester);

    final passwordField = find.byType(TextFormField).at(1);
    await tester.enterText(passwordField, 'short');
    await tester.pump();

    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    // Still nothing demanded of the field below it.
    expect(find.text('Please confirm your password'), findsNothing);
  });

  testWidgets('submitting still reports every missing field', (tester) async {
    await pumpForm(tester);

    formKey.currentState!.validate();
    await tester.pump();

    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(find.text('Please confirm your password'), findsOneWidget);
  });
}
