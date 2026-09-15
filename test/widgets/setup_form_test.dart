import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/username_rules.dart';
import 'package:quark/widgets/setup/setup_form.dart';

/// #1946: the Quark refuses a new username outside its rule with 400, so the
/// setup and request-account forms check the same rule before sending, and
/// never rewrite what was typed.
void main() {
  group('validateNewUsername', () {
    for (final good in ['bob', 'ada.lovelace', 'r2-d2', 'x_1', 'a' * 32]) {
      test('accepts "$good"', () => expect(validateNewUsername(good), isNull));
    }

    for (final bad in ['Bob', '.bob', '_bob', 'bo b', 'a/b', 'a' * 33]) {
      test('refuses "$bad"', () {
        expect(validateNewUsername(bad), Errors.invalidUsername);
      });
    }

    test('asks for a username when there is none', () {
      expect(validateNewUsername('  '), 'Username is required');
    });

    test('ignores the spaces the form trims anyway', () {
      expect(validateNewUsername(' bob '), isNull);
    });
  });

  group('SetupForm', () {
    late GlobalKey<FormState> formKey;
    late List<String> submitted;
    final username = TextEditingController();
    final password = TextEditingController();
    final confirm = TextEditingController();

    setUp(() {
      formKey = GlobalKey<FormState>();
      submitted = [];
      username.clear();
      password.clear();
      confirm.clear();
    });

    Future<void> pumpForm(
      WidgetTester tester, {
      String? title,
      String? submitLabel,
    }) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final focus = [FocusNode(), FocusNode(), FocusNode()];
      addTearDown(() {
        for (final node in focus) {
          node.dispose();
        }
      });

      final form = title == null
          ? SetupForm(
              formKey: formKey,
              usernameController: username,
              passwordController: password,
              confirmController: confirm,
              usernameFocus: focus[0],
              passwordFocus: focus[1],
              confirmFocus: focus[2],
              obscurePassword: true,
              obscureConfirm: true,
              loading: false,
              error: null,
              onTogglePassword: () {},
              onToggleConfirm: () {},
              onSubmit: () {
                if (formKey.currentState!.validate()) {
                  submitted.add(username.text.trim());
                }
              },
            )
          : SetupForm(
              title: title,
              subtitle: 'An admin approves new accounts.',
              submitLabel: submitLabel!,
              formKey: formKey,
              usernameController: username,
              passwordController: password,
              confirmController: confirm,
              usernameFocus: focus[0],
              passwordFocus: focus[1],
              confirmFocus: focus[2],
              obscurePassword: true,
              obscureConfirm: true,
              loading: false,
              error: null,
              onTogglePassword: () {},
              onToggleConfirm: () {},
              onSubmit: () {},
            );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: form)),
        ),
      );
    }

    Future<void> fillAndSubmit(WidgetTester tester, String name) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        name,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'hunter2hunter2',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'),
        'hunter2hunter2',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
    }

    testWidgets('states the username rule up front', (tester) async {
      await pumpForm(tester);

      expect(find.text(newUsernameHint), findsOneWidget);
    });

    testWidgets('refuses an uppercase username and leaves it as typed', (
      tester,
    ) async {
      await pumpForm(tester);

      await fillAndSubmit(tester, 'Ada');

      expect(submitted, isEmpty);
      expect(find.text(Errors.invalidUsername), findsOneWidget);
      expect(username.text, 'Ada');
      expect(tester.takeException(), isNull);
    });

    testWidgets('submits a username the Quark accepts', (tester) async {
      await pumpForm(tester);

      await fillAndSubmit(tester, 'ada');

      expect(submitted, ['ada']);
    });

    testWidgets('takes its heading and button label from the caller', (
      tester,
    ) async {
      await pumpForm(
        tester,
        title: 'Request an account',
        submitLabel: 'Send request',
      );

      expect(find.text('Request an account'), findsOneWidget);
      expect(find.text('An admin approves new accounts.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send request'), findsOneWidget);
      expect(find.text('Set up your quark'), findsNothing);
    });
  });
}
