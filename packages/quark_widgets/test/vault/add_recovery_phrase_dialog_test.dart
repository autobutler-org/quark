import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const phraseField = ValueKey('add_recovery_phrase_phrase');
  const passwordField = ValueKey('add_recovery_phrase_password');
  const submit = ValueKey('add_recovery_phrase_submit');
  const cancel = ValueKey('add_recovery_phrase_cancel');

  testBothViewports('hands over the phrase and the password once both are '
      'typed', (tester, size) async {
    final submitted = <(String, String)>[];
    await pumpAt(
      tester,
      AddRecoveryPhraseDialog(
        onSubmit: (phrase, password) => submitted.add((phrase, password)),
        onCancel: () {},
      ),
      size: size,
    );

    await tester.tap(find.byKey(submit));
    await tester.enterText(find.byKey(phraseField), '  apple bread cloud ');
    await tester.tap(find.byKey(submit));
    expect(submitted, isEmpty, reason: 'no password yet');

    await tester.enterText(find.byKey(passwordField), 'pw');
    await tester.tap(find.byKey(submit));
    expect(submitted, [('apple bread cloud', 'pw')]);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('shows the caller\'s error and reports cancel', (
    tester,
    size,
  ) async {
    var canceled = 0;
    await pumpAt(
      tester,
      AddRecoveryPhraseDialog(
        error: "That isn't your account's recovery phrase.",
        onSubmit: (_, _) {},
        onCancel: () => canceled++,
      ),
      size: size,
    );

    expect(
      find.text("That isn't your account's recovery phrase."),
      findsOneWidget,
    );
    await tester.tap(find.byKey(cancel));
    expect(canceled, 1);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('holds both buttons while busy', (tester, size) async {
    final submitted = <String>[];
    await pumpAt(
      tester,
      AddRecoveryPhraseDialog(
        isBusy: true,
        onSubmit: (phrase, _) => submitted.add(phrase),
        onCancel: () => submitted.add('cancel'),
      ),
      size: size,
    );

    await tester.enterText(find.byKey(phraseField), 'apple');
    await tester.enterText(find.byKey(passwordField), 'pw');
    await tester.tap(find.byKey(submit));
    await tester.tap(find.byKey(cancel));
    expect(submitted, isEmpty);
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
