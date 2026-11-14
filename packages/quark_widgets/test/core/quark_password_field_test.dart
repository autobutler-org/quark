import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one password box behind sign-in, setup, recovery, the account dialogs
/// and the vault entry form (#4102): it owns hiding the text and the button
/// that shows it, so no screen keeps a flag of its own.
void main() {
  const fieldKey = ValueKey('thing_password');
  const visibilityKey = ValueKey('thing_password_visibility');

  bool obscured(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(fieldKey),
          matching: find.byType(EditableText),
        ),
      )
      .obscureText;

  testBothViewports('lays out with the label, lock and show button', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkPasswordField(
        key: fieldKey,
        labelText: 'Password',
        helperText: 'At least 8 characters',
        showLockIcon: true,
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.lock_outline), findsOneWidget);
    expect(find.byIcon(QuarkIcons.visibility), findsOneWidget);
  });

  testWidgets('hides the text until the show button is pressed', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkPasswordField(
        key: fieldKey,
        hintText: 'Current password',
        visibilityLabel: 'current password',
        visibilityKey: visibilityKey,
      ),
    );

    expect(obscured(tester), isTrue);
    expect(find.byTooltip('Show current password'), findsOneWidget);

    await tester.tap(find.byKey(visibilityKey));
    await tester.pump();

    expect(obscured(tester), isFalse);
    expect(find.byTooltip('Hide current password'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.visibility_off), findsOneWidget);
  });

  testWidgets('reports edits and the submit once each', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkPasswordField(
        key: fieldKey,
        onChanged: (text) => events.add('changed($text)'),
        onSubmitted: (text) => events.add('submitted($text)'),
      ),
    );

    await tester.enterText(find.byKey(fieldKey), 'hunter22');
    await tester.testTextInput.receiveAction(TextInputAction.done);

    expect(events, ['changed(hunter22)', 'submitted(hunter22)']);
  });

  testWidgets('shows the validator error inside a form', (tester) async {
    final form = GlobalKey<FormState>();
    await pumpAt(
      tester,
      Form(
        key: form,
        child: QuarkPasswordField(
          key: fieldKey,
          validator: (v) =>
              (v == null || v.isEmpty) ? 'Password is required' : null,
        ),
      ),
    );

    form.currentState!.validate();
    await tester.pump();

    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('the trailing slot can show what it wrote', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpAt(
      tester,
      QuarkPasswordField(
        key: fieldKey,
        controller: controller,
        trailingBuilder: (context, reveal) => IconButton(
          key: const ValueKey('thing_generate'),
          tooltip: 'Generate password',
          icon: const Icon(QuarkIcons.casino),
          onPressed: () {
            controller.text = 'Generated#1';
            reveal();
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('thing_generate')));
    await tester.pump();

    expect(find.text('Generated#1'), findsOneWidget);
    expect(obscured(tester), isFalse);
  });

  testWidgets('every icon-only button carries a tooltip', (tester) async {
    await pumpAt(
      tester,
      QuarkPasswordField(
        key: fieldKey,
        trailingBuilder: (context, reveal) => IconButton(
          tooltip: 'Generate password',
          icon: const Icon(QuarkIcons.casino),
          onPressed: reveal,
        ),
      ),
    );

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull);
    }
  });
}
