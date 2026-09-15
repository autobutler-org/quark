import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Adding an account from the Users page (#1873). The Quark refuses a
/// username outside its rule with 400, so the dialog checks the same rule
/// before anything is sent, and never rewrites what was typed.
void main() {
  Future<List<CreateUserInput>> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    List<String>? events,
    bool isSubmitting = false,
    String? error,
    Brightness brightness = Brightness.dark,
  }) async {
    final submitted = <CreateUserInput>[];
    await pumpAt(
      tester,
      CreateUserDialog(
        onSubmit: submitted.add,
        onCancel: () => events?.add('cancel'),
        isSubmitting: isSubmitting,
        error: error,
      ),
      size: size,
      brightness: brightness,
    );
    return submitted;
  }

  Future<void> fill(
    WidgetTester tester, {
    String username = 'bob',
    String password = 'correct horse',
    String? confirm,
  }) async {
    await tester.enterText(
      find.byKey(const ValueKey('create_user_username')),
      username,
    );
    await tester.enterText(
      find.byKey(const ValueKey('create_user_password')),
      password,
    );
    await tester.enterText(
      find.byKey(const ValueKey('create_user_confirm')),
      confirm ?? password,
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('create_user_submit')),
    );
    await tester.tap(find.byKey(const ValueKey('create_user_submit')));
    await tester.pump();
  }

  testBothViewports('hands back what was typed, with a folder by default', (
    tester,
    size,
  ) async {
    final submitted = await pumpDialog(tester, size: size);

    await fill(tester);
    await submit(tester);

    expect(submitted, const [
      CreateUserInput(username: 'bob', password: 'correct horse'),
    ]);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('leaves the folder out when the box is cleared', (
    tester,
    size,
  ) async {
    final submitted = await pumpDialog(tester, size: size);

    await fill(tester, username: 'cy.lee');
    await tester.ensureVisible(
      find.byKey(const ValueKey('create_user_private_folder')),
    );
    await tester.tap(find.byKey(const ValueKey('create_user_private_folder')));
    await tester.pump();
    await submit(tester);

    expect(submitted, const [
      CreateUserInput(
        username: 'cy.lee',
        password: 'correct horse',
        createFolder: false,
      ),
    ]);
  });

  for (final bad in ['Bob', '.bob', 'bo b', 'a/b', 'x' * 33]) {
    testWidgets('refuses the username "$bad" before sending anything', (
      tester,
    ) async {
      final submitted = await pumpDialog(tester, size: narrowViewport);

      await fill(tester, username: bad);
      await submit(tester);

      expect(submitted, isEmpty);
      expect(
        find.textContaining('Use up to 32 lowercase letters'),
        findsOneWidget,
      );
      // Never silently lowercased.
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('create_user_username')),
            )
            .controller
            ?.text,
        bad,
      );
    });
  }

  testBothViewports('refuses a short password and a mismatched confirm', (
    tester,
    size,
  ) async {
    final submitted = await pumpDialog(tester, size: size);

    await fill(tester, password: 'short', confirm: 'shirt');
    await submit(tester);

    expect(submitted, isEmpty);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testBothViewports('cancels through its key', (tester, size) async {
    final events = <String>[];
    await pumpDialog(tester, size: size, events: events);

    await tester.tap(find.byKey(const ValueKey('create_user_cancel')));
    await tester.pump();

    expect(events, ['cancel']);
  });

  testWidgets('holds both buttons while submitting', (tester) async {
    final events = <String>[];
    final submitted = await pumpDialog(
      tester,
      isSubmitting: true,
      events: events,
    );

    await fill(tester);
    await submit(tester);
    await tester.tap(find.byKey(const ValueKey('create_user_cancel')));
    await tester.pump();

    expect(submitted, isEmpty);
    expect(events, isEmpty);
  });

  testBothViewports('shows the refusal the caller handed it', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size, error: 'That username is taken.');

    expect(find.text('That username is taken.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the refusal reads in the error color', (tester) async {
      await pumpDialog(tester, error: 'Nope.', brightness: brightness);

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text('Nope.')).style?.color,
        tokens.error,
      );
    });
  }
}
