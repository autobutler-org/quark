import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The notice over the composer (#2495): each encryption state says what it
/// is and what to do next, in its own words, at both sizes.
void main() {
  const checkAgain = ValueKey('encryption_notice_check_again');
  const learnMore = ValueKey('encryption_notice_learn_more');

  for (final status in ChatEncryptionStatus.values) {
    testBothViewports('${status.name} reads as its own state', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: QuarkEncryptionNotice(status: status, onLearnMore: () {}),
        ),
        size: size,
      );

      expect(find.text(QuarkEncryptionNotice.titleOf(status)), findsOneWidget);
      expect(find.text(QuarkEncryptionNotice.bodyOf(status)), findsOneWidget);
      expect(find.byKey(learnMore), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('every state has its own title and next step', () {
    final titles = ChatEncryptionStatus.values.map(
      QuarkEncryptionNotice.titleOf,
    );
    final bodies = ChatEncryptionStatus.values.map(
      QuarkEncryptionNotice.bodyOf,
    );
    expect(titles.toSet(), hasLength(ChatEncryptionStatus.values.length));
    expect(bodies.toSet(), hasLength(ChatEncryptionStatus.values.length));
  });

  testBothViewports('waiting offers check again and learn more', (
    tester,
    size,
  ) async {
    final log = <String>[];
    await pumpAt(
      tester,
      QuarkEncryptionNotice(
        status: ChatEncryptionStatus.waitingForKey,
        onCheckAgain: () => log.add('check'),
        onLearnMore: () => log.add('learn'),
      ),
      size: size,
    );

    await tester.tap(find.byKey(checkAgain));
    await tester.tap(find.byKey(learnMore));
    expect(log, ['check', 'learn']);
  });

  testBothViewports('checking holds the button still with a loader', (
    tester,
    size,
  ) async {
    final log = <String>[];
    await pumpAt(
      tester,
      QuarkEncryptionNotice(
        status: ChatEncryptionStatus.waitingForKey,
        isChecking: true,
        onCheckAgain: () => log.add('check'),
      ),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    await tester.tap(find.byKey(checkAgain), warnIfMissed: false);
    expect(log, isEmpty);
  });

  testBothViewports('check again is only for waiting', (tester, size) async {
    await pumpAt(
      tester,
      QuarkEncryptionNotice(
        status: ChatEncryptionStatus.unverifiedKey,
        onCheckAgain: () {},
      ),
      size: size,
    );

    expect(find.byKey(checkAgain), findsNothing);
    expect(find.byKey(learnMore), findsNothing);
  });
}
