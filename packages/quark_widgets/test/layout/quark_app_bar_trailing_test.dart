import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The app-wide trailing slot `QuarkAppBar` reads after a page's own actions.
void main() {
  const bar = Scaffold(
    appBar: QuarkAppBar(
      label: 'Photos',
      icon: QuarkIcons.photo_library_outlined,
      actions: [Text('page action')],
    ),
    body: SizedBox.shrink(),
  );

  testBothViewports('with no scope the bar shows only its own actions', (
    tester,
    size,
  ) async {
    await pumpAt(tester, bar, size: size, scaffold: false);
    expect(find.text('page action'), findsOneWidget);
    expect(find.text('app action'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a scope appends its actions after the page actions', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkAppBarTrailing(actions: [Text('app action')], child: bar),
      size: size,
      scaffold: false,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.text('page action')).left,
      lessThan(tester.getRect(find.text('app action')).left),
    );
  });

  testWidgets('bars rebuild when the scope changes its actions', (
    tester,
  ) async {
    Widget scoped(String label) =>
        QuarkAppBarTrailing(actions: [Text(label)], child: bar);
    await pumpAt(tester, scoped('one'), scaffold: false);
    expect(find.text('one'), findsOneWidget);

    await pumpAt(tester, scoped('two'), scaffold: false);
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
  });
}
