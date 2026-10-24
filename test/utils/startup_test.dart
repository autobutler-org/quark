import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/startup.dart';
import 'package:quark/widgets/layout/startup_loader.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #2066: nothing was painted until the saved settings had loaded, so a load
/// that stalled left the blank native launch screen up.
void main() {
  const grace = Duration(seconds: 1);

  testWidgets('a load that never finishes still gets its notice', (
    tester,
  ) async {
    var notices = 0;
    unawaited(
      awaitWithSlowNotice(
        Completer<void>().future,
        grace: grace,
        onSlow: () => notices++,
      ),
    );

    await tester.pump(grace - const Duration(milliseconds: 1));
    expect(notices, 0);

    await tester.pump(const Duration(minutes: 5));
    expect(notices, 1);
  });

  // A timer left running fails these two: the binding checks for one when a
  // test ends.
  testWidgets('a load that finishes within the grace gets no notice', (
    tester,
  ) async {
    var notices = 0;
    final load = Completer<int>();
    final result = awaitWithSlowNotice(
      load.future,
      grace: grace,
      onSlow: () => notices++,
    );

    load.complete(7);
    expect(await result, 7);
    await tester.pump(grace * 2);

    expect(notices, 0);
  });

  testWidgets('a failed load passes its error on and gets no notice', (
    tester,
  ) async {
    var notices = 0;
    final load = Completer<void>();
    final result = awaitWithSlowNotice(
      load.future,
      grace: grace,
      onSlow: () => notices++,
    );

    load.completeError(StateError('no storage'));
    await expectLater(result, throwsStateError);
    await tester.pump(grace * 2);

    expect(notices, 0);
  });

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('the startup loader builds on its own ($name)', (tester) async {
      setViewport(tester, size);

      await tester.pumpWidget(const StartupLoader());

      expect(find.byType(QuarkLoader), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
