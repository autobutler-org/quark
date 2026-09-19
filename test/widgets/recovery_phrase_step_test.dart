import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/setup/recovery_phrase_step.dart';

/// #2023: the step warned "don't store it digitally on this device" directly
/// above a Copy button — a contradiction on the one screen where a user is
/// deciding whether to trust what they just set up. The guidance and the
/// buttons have to agree.
void main() {
  Future<void> pumpStep(
    WidgetTester tester, {
    bool acknowledged = false,
    VoidCallback? onContinue,
  }) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecoveryPhraseStep(
              phrase: 'alpha bravo charlie delta echo foxtrot',
              acknowledged: acknowledged,
              onAcknowledgedChanged: (_) {},
              onContinue: onContinue ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the guidance does not contradict the copy button', (
    tester,
  ) async {
    await pumpStep(tester);

    expect(find.textContaining("don't store it digitally"), findsNothing);
    expect(find.textContaining('password manager'), findsWidgets);
  });

  testWidgets('the copy button says where the phrase should go', (
    tester,
  ) async {
    await pumpStep(tester);

    expect(find.text('Copy to a password manager'), findsOneWidget);
    // And what the clipboard costs, next to the button it is about.
    expect(find.textContaining('clipboard is shared'), findsOneWidget);
  });

  testWidgets('the acknowledgement covers saving it, however it was saved', (
    tester,
  ) async {
    await pumpStep(tester);

    expect(
      find.text('I have saved my recovery phrase somewhere safe.'),
      findsOneWidget,
    );
  });

  testWidgets('continue stays locked until the box is ticked', (tester) async {
    await pumpStep(tester);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await pumpStep(tester, acknowledged: true);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
