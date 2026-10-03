import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart';

/// #2576: the Photos library names its way into Duplicates on screen — a
/// "Duplicates" chip on a wide screen, a "Tools" menu on a phone — instead of
/// a copy icon in the top row whose name only a hover could reveal.
void main() {
  Future<void> pumpPhotos(WidgetTester tester, Size size) async {
    setViewport(tester, size);
    await tester.pumpWidget(const MaterialApp(home: PhotosPage()));
    await tester.pump();
  }

  testWidgets('a wide library shows a Duplicates chip in its second row', (
    tester,
  ) async {
    await pumpPhotos(tester, wideViewport);

    expect(tester.takeException(), isNull);
    final row = find.byType(QuarkAppBarBottom);
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('photos_duplicates')),
        matching: find.text('Duplicates'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a phone library keeps Duplicates behind a labeled menu', (
    tester,
  ) async {
    await pumpPhotos(tester, narrowViewport);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('photos_duplicates')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('app_bar_bottom_menu')),
        matching: find.text('Tools'),
      ),
      findsOneWidget,
    );
  });
}
