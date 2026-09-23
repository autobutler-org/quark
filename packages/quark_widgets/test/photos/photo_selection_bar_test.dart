import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('counts the selection and adds it to an album', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      PhotoSelectionBar(
        selectedCount: 3,
        onAddToAlbum: () => events.add('add'),
      ),
      size: size,
    );

    expect(find.text('3 photos selected'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('photo_selection_add_to_album')),
    );
    await tester.pump();

    expect(events, ['add']);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('keeps the action flush with the right edge', (tester) async {
    // The bar trades its Spacers for spaceBetween so the button can give up
    // label width on a narrow phone; this pins the wide layout it replaced.
    await pumpAt(
      tester,
      PhotoSelectionBar(selectedCount: 3, onAddToAlbum: () {}),
      size: wideViewport,
    );

    expect(
      tester
          .getRect(find.byKey(const ValueKey('photo_selection_add_to_album')))
          .right,
      closeTo(tester.getRect(find.byType(PhotoSelectionBar)).right - 16, 1),
    );
  });

  testWidgets('says "photo" for exactly one', (tester) async {
    await pumpAt(
      tester,
      PhotoSelectionBar(selectedCount: 1, onAddToAlbum: () {}),
      size: narrowViewport,
    );

    expect(find.text('1 photo selected'), findsOneWidget);
  });

  testBothViewports('refuses to open the picker with nothing selected', (
    tester,
    size,
  ) async {
    var adds = 0;
    await pumpAt(
      tester,
      PhotoSelectionBar(selectedCount: 0, onAddToAlbum: () => adds++),
      size: size,
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('photo_selection_add_to_album')),
    );
    expect(button.onPressed, isNull);
    expect(adds, 0);
  });
}
