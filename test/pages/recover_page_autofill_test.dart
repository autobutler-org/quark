import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/recover_page.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

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
    testWidgets('$name: username and new passwords share one autofill group', (
      tester,
    ) async {
      setViewport(tester, size);

      await tester.pumpWidget(const MaterialApp(home: RecoverPage()));
      await tester.pumpAndSettle();

      final group = groupOf(tester, 'Username');
      expect(group, isNotNull, reason: 'Username sits in no AutofillGroup');
      expect(groupOf(tester, 'New password'), same(group));
      expect(groupOf(tester, 'Confirm new password'), same(group));

      final hints = [
        for (final client in group!.autofillClients)
          ...client.textInputConfiguration.autofillConfiguration.autofillHints,
      ];
      expect(
        hints,
        unorderedEquals([
          AutofillHints.username,
          AutofillHints.newPassword,
          AutofillHints.newPassword,
        ]),
      );
    });
  }
}
