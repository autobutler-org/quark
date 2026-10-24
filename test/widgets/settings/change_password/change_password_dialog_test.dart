import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/change_password/change_password_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' show setViewport;

/// #3022: the dialog collects the current password and the new one twice. It
/// refuses to send a new password that is too short, unchanged or typed two
/// different ways, and otherwise only reports what it was given: the Quark
/// checks the current password.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final currentField = find.byKey(
    const ValueKey('change_password_current_field'),
  );
  final newField = find.byKey(const ValueKey('change_password_new_field'));
  final confirmField = find.byKey(
    const ValueKey('change_password_confirm_field'),
  );
  final errorText = find.byKey(const ValueKey('change_password_error'));
  final cancel = find.byKey(const ValueKey('change_password_cancel'));
  final submit = find.byKey(const ValueKey('change_password_submit'));

  /// What the dialog called back with, in order.
  late List<String> calls;

  Future<void> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    bool isWorking = false,
    String? error,
  }) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangePasswordDialog(
            isWorking: isWorking,
            error: error,
            onSubmit: (current, next) => calls.add('submit $current -> $next'),
            onCancel: () => calls.add('cancel'),
          ),
        ),
      ),
    );
  }

  Future<void> type(
    WidgetTester tester, {
    String? current,
    String? next,
    String? confirm,
  }) async {
    if (current != null) await tester.enterText(currentField, current);
    if (next != null) await tester.enterText(newField, next);
    if (confirm != null) await tester.enterText(confirmField, confirm);
    await tester.pump();
  }

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<ButtonStyleButton>(button).onPressed != null;

  bool obscured(WidgetTester tester, Finder field) => tester
      .widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      )
      .obscureText;

  setUp(() => calls = []);

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets('submit waits for all three fields at $size', (tester) async {
      await pumpDialog(tester, size: size);

      expect(tester.takeException(), isNull);
      expect(enabled(tester, submit), isFalse);
      expect(errorText, findsNothing);

      await type(tester, current: 'old-password');
      expect(enabled(tester, submit), isFalse);
      await type(tester, next: 'new-password');
      expect(enabled(tester, submit), isFalse);
      await type(tester, confirm: 'new-password');
      expect(enabled(tester, submit), isTrue);
      expect(errorText, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a valid entry is sent once, as typed, at $size', (
      tester,
    ) async {
      await pumpDialog(tester, size: size);
      await type(
        tester,
        current: 'old-password',
        next: 'new-password',
        confirm: 'new-password',
      );

      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(calls, ['submit old-password -> new-password']);
    });

    testWidgets('a new password that is too short is refused at $size', (
      tester,
    ) async {
      await pumpDialog(tester, size: size);
      await type(
        tester,
        current: 'old-password',
        next: 'short',
        confirm: 'short',
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(errorText).data, Errors.passwordTooShort);
      expect(enabled(tester, submit), isFalse);
    });

    testWidgets('two different new passwords are refused at $size', (
      tester,
    ) async {
      await pumpDialog(tester, size: size);
      await type(
        tester,
        current: 'old-password',
        next: 'new-password',
        confirm: 'new-password-2',
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(errorText).data, Errors.passwordsDontMatch);
      expect(enabled(tester, submit), isFalse);

      // The done key must not get around the disabled button.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(calls, isEmpty);
    });

    testWidgets('the current password again is refused at $size', (
      tester,
    ) async {
      await pumpDialog(tester, size: size);
      await type(
        tester,
        current: 'old-password',
        next: 'old-password',
        confirm: 'old-password',
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(errorText).data, Errors.passwordUnchanged);
      expect(enabled(tester, submit), isFalse);
    });

    testWidgets('a change in flight locks the dialog and shows a loader at '
        '$size', (tester) async {
      await pumpDialog(tester, size: size, isWorking: true);

      expect(tester.takeException(), isNull);
      expect(enabled(tester, cancel), isFalse);
      expect(enabled(tester, submit), isFalse);
      expect(
        find.descendant(of: submit, matching: find.byType(QuarkLoader)),
        findsOneWidget,
      );
    });

    testWidgets('the last failure is shown at $size', (tester) async {
      await pumpDialog(tester, size: size, error: Errors.wrongCurrentPassword);

      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(errorText).data, Errors.wrongCurrentPassword);
    });

    testWidgets('cancel backs out at $size', (tester) async {
      await pumpDialog(tester, size: size);

      await tester.ensureVisible(cancel);
      await tester.tap(cancel);

      expect(tester.takeException(), isNull);
      expect(calls, ['cancel']);
    });
  }

  testWidgets('a problem with what is typed now outranks the last failure', (
    tester,
  ) async {
    await pumpDialog(tester, error: Errors.wrongCurrentPassword);
    await type(tester, current: 'old-password', next: 'short');

    expect(tester.widget<Text>(errorText).data, Errors.passwordTooShort);
  });

  testWidgets('each field hides what is typed until its toggle is used', (
    tester,
  ) async {
    await pumpDialog(tester);

    for (final (prefix, label) in [
      ('change_password_current', 'current password'),
      ('change_password_new', 'new password'),
      ('change_password_confirm', 'confirm new password'),
    ]) {
      final field = find.byKey(ValueKey('${prefix}_field'));
      final toggle = find.byKey(ValueKey('${prefix}_visibility'));

      expect(obscured(tester, field), isTrue, reason: prefix);
      expect(tester.widget<IconButton>(toggle).tooltip, 'Show $label');

      await tester.tap(toggle);
      await tester.pump();
      expect(obscured(tester, field), isFalse, reason: prefix);
      expect(tester.widget<IconButton>(toggle).tooltip, 'Hide $label');

      await tester.tap(toggle);
      await tester.pump();
      expect(obscured(tester, field), isTrue, reason: prefix);
    }
  });

  testWidgets('cancel and submit carry tooltips', (tester) async {
    await pumpDialog(tester);

    for (final button in [cancel, submit]) {
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: button, matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, isNotEmpty);
    }
  });
}
