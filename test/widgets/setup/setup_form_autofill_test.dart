import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/setup/setup_form.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #3591: on web, Flutter puts a real `<input>` in the DOM only for the
/// focused field, plus one for every other field in that field's
/// [AutofillGroup]. Without a group, a password manager found no password
/// input beside the username one.
void main() {
  AutofillGroupState? groupOf(WidgetTester tester, String label) {
    final editable = find.descendant(
      of: find.widgetWithText(TextFormField, label),
      matching: find.byType(EditableText),
    );
    return tester.state<EditableTextState>(editable).currentAutofillScope
        as AutofillGroupState?;
  }

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: the account fields share one autofill group', (
      tester,
    ) async {
      setViewport(tester, size);

      final controllers = List.generate(3, (_) => TextEditingController());
      final focuses = List.generate(3, (_) => FocusNode());
      addTearDown(() {
        for (final c in controllers) {
          c.dispose();
        }
        for (final f in focuses) {
          f.dispose();
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SetupForm(
                formKey: GlobalKey<FormState>(),
                usernameController: controllers[0],
                passwordController: controllers[1],
                confirmController: controllers[2],
                usernameFocus: focuses[0],
                passwordFocus: focuses[1],
                confirmFocus: focuses[2],
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
      await tester.pumpAndSettle();

      final group = groupOf(tester, 'Username');
      expect(group, isNotNull, reason: 'Username sits in no AutofillGroup');
      expect(groupOf(tester, 'Password'), same(group));
      expect(groupOf(tester, 'Confirm password'), same(group));

      final hints = [
        for (final client in group!.autofillClients)
          ...client.textInputConfiguration.autofillConfiguration.autofillHints,
      ];
      expect(
        hints,
        unorderedEquals([
          AutofillHints.newUsername,
          AutofillHints.newPassword,
          AutofillHints.newPassword,
        ]),
      );
    });
  }
}
