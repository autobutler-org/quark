import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/recover_page.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2031: setup shows a strength meter while a password is chosen; the
/// recovery form asked for a new password with nothing but "At least 8
/// characters". The two screens ask for the same thing and should help the
/// same way — a password chosen under stress is the one most likely to be
/// weak.
void main() {
  Future<void> pumpRecover(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: RecoverPage(onRecoverSuccess: null)),
    );
    await tester.pumpAndSettle();
  }

  Finder passwordField() => find.widgetWithText(TextFormField, 'New password');

  testWidgets('the meter is on the form', (tester) async {
    await pumpRecover(tester);

    expect(find.byType(PasswordStrengthBar), findsOneWidget);
  });

  testWidgets('it follows what is typed', (tester) async {
    await pumpRecover(tester);

    await tester.enterText(passwordField(), 'short');
    await tester.pumpAndSettle();
    expect(find.text('Weak'), findsOneWidget);

    await tester.enterText(passwordField(), 'Correct-Horse-Battery-9');
    await tester.pumpAndSettle();
    expect(find.text('Weak'), findsNothing);
  });

  testWidgets('an empty field is not called weak', (tester) async {
    await pumpRecover(tester);

    expect(find.text('Weak'), findsNothing);
  });
}
