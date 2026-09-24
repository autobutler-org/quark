import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/settings/delete_account_dialog.dart';

/// #1762: App Store Review Guideline 5.1.1(v) needs deletion initiated in the
/// app, and a destructive action needs friction in front of it. These pin the
/// friction — the account's password (#2346) — and the two things the dialog must not
/// do: reach anything but the account, or stay quiet about the files it leaves
/// behind for whoever sets the Quark up next.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final passwordField = find.byKey(
    const ValueKey('delete_account_password_field'),
  );
  final visibility = find.byKey(
    const ValueKey('delete_account_password_visibility'),
  );
  final filesWarning = find.byKey(
    const ValueKey('delete_account_files_warning'),
  );
  final submit = find.byKey(const ValueKey('delete_account_submit'));
  final cancel = find.byKey(const ValueKey('delete_account_cancel'));

  /// Pumps the dialog at [size] and returns the confirmations it emits.
  Future<List<String>> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    String? username = 'ada',
    List<String>? events,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final confirmations = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeleteAccountDialog(
            username: username,
            onConfirm: confirmations.add,
            onCancel: () => events?.add('cancel'),
          ),
        ),
      ),
    );
    await tester.pump();
    return confirmations;
  }

  /// Runs [body] against both viewports every widget has to survive.
  void testBothViewports(
    String description,
    Future<void> Function(WidgetTester tester, Size size) body,
  ) {
    for (final size in [narrowViewport, wideViewport]) {
      final label = size == narrowViewport ? 'narrow' : 'wide';
      testWidgets('$description ($label)', (tester) => body(tester, size));
    }
  }

  testBothViewports('names the account it is about to delete', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size);

    expect(
      find.textContaining('The account ada will be deleted'),
      findsOneWidget,
    );
    expect(find.text('Delete my account'), findsOneWidget);
  });

  testBothViewports('offers nothing that reaches the appliance', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size);

    // Deleting an account and resetting a Quark are two intents. There is no
    // control here that can turn the first into the second.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testBothViewports('does not confirm until a password is typed', (
    tester,
    size,
  ) async {
    final confirmations = await pumpDialog(tester, size: size);

    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(submit);
    await tester.pump();

    expect(confirmations, isEmpty);
  });

  // The username is on the screen; knowing it proves nothing (#2346).
  testBothViewports('asks for the password, not the username', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size);

    expect(find.text('Enter your password to confirm.'), findsOneWidget);
    expect(find.textContaining('Type ada'), findsNothing);
  });

  testBothViewports('sends the typed password', (tester, size) async {
    final confirmations = await pumpDialog(tester, size: size);

    await tester.enterText(passwordField, 'hunter2hunter2');
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();

    expect(confirmations, ['hunter2hunter2']);
  });

  testWidgets('hides the password until asked to show it', (tester) async {
    await pumpDialog(tester, size: narrowViewport);
    bool obscured() => tester
        .widget<EditableText>(
          find.descendant(
            of: passwordField,
            matching: find.byType(EditableText),
          ),
        )
        .obscureText;

    expect(obscured(), isTrue);
    await tester.ensureVisible(visibility);
    await tester.pump();
    await tester.tap(visibility);
    await tester.pump();
    expect(obscured(), isFalse);
  });

  testBothViewports('warns that the files outlive the account', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size);

    expect(filesWarning, findsOneWidget);
    expect(find.text(kDeleteAccountFilesWarning), findsOneWidget);
    // Naming the remedy, since this dialog deliberately cannot apply it.
    expect(kDeleteAccountFilesWarning, contains('Reset this Quark'));
  });

  testWidgets('says the Quark returns to setup when this is the last account', (
    tester,
  ) async {
    await pumpDialog(tester, size: narrowViewport);

    expect(find.textContaining('the Quark returns to setup'), findsOneWidget);
  });

  testWidgets('still asks for the password when no username is known', (
    tester,
  ) async {
    final confirmations = await pumpDialog(
      tester,
      size: narrowViewport,
      username: null,
    );

    expect(find.textContaining('Your account will be deleted'), findsOneWidget);
    await tester.enterText(passwordField, 'hunter2hunter2');
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();

    expect(confirmations, ['hunter2hunter2']);
  });

  testWidgets('cancels without confirming', (tester) async {
    final events = <String>[];
    final confirmations = await pumpDialog(
      tester,
      size: narrowViewport,
      events: events,
    );

    await tester.tap(cancel);
    await tester.pump();

    expect(events, ['cancel']);
    expect(confirmations, isEmpty);
  });
}
