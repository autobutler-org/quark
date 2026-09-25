import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/setup/setup_form.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2021: rebuilding the password field on every keystroke restarts the
/// decorator's helper/error fade, so "At least 8 characters" overlaps the
/// length error while a password is typed. The length error is a different
/// string ("Password must be at least 8 characters"), so an exact match and
/// [find.textContaining] for the helper must both stay at one.
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
              onSubmit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final passwordField = find.widgetWithText(TextFormField, 'Password');

  testWidgets('the helper stays single while a password is typed', (
    tester,
  ) async {
    await pumpForm(tester);

    await tester.tap(passwordField);
    await tester.pump();

    await tester.enterText(passwordField, 'short');
    await tester.pump();
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.textContaining('At least 8 characters'), findsOneWidget);

    await tester.enterText(passwordField, 'abcdefghijkl1!');
    await tester.pump();
    expect(find.text('At least 8 characters'), findsOneWidget);

    // The frames right after the value crosses 8 characters, before the
    // decorator's fade has settled.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('At least 8 characters'), findsOneWidget);
    expect(find.byType(PasswordStrengthBar), findsOneWidget);
    expect(find.text('Very strong'), findsOneWidget);
  });

  testWidgets('a touched confirm field follows later password edits', (
    tester,
  ) async {
    await pumpForm(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'abcdefghijkl1!',
    );
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);

    await tester.enterText(passwordField, 'abcdefghijkl1!');
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsNothing);
    expect(find.text('At least 8 characters'), findsOneWidget);

    await tester.enterText(passwordField, 'abcdefghijkl2!');
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.textContaining('At least 8 characters'), findsOneWidget);
    expect(find.text('Very strong'), findsOneWidget);
  });
}
