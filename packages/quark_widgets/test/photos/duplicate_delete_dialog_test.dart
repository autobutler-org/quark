import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The confirmation before marked duplicates move to the trash (#3362): it
/// names every copy, however many, and keeps its buttons reachable.
void main() {
  List<DuplicatePhotoItem> copies(int n) => [
    for (var i = 0; i < n; i++)
      DuplicatePhotoItem(id: 'c$i', name: 'beach $i.jpg', location: 'Backups'),
  ];

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<DuplicatePhotoItem> photos,
    Size size = wideViewport,
    List<String>? events,
  }) => pumpAt(
    tester,
    DuplicateDeleteDialog(
      photos: photos,
      body: 'They move to Trash. You can restore them for 30 days.',
      onConfirm: () => events?.add('confirm'),
      onCancel: () => events?.add('cancel'),
    ),
    size: size,
  );

  testBothViewports('titles the count and lists every copy with its place', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size, photos: copies(3));

    expect(tester.takeException(), isNull);
    expect(find.text('Move 3 photos to Trash?'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('duplicate_delete_item_c$i')), findsOne);
      expect(find.text('beach $i.jpg'), findsOneWidget);
    }
    expect(find.text('Backups'), findsNWidgets(3));
  });

  testWidgets('says photo for one', (tester) async {
    await pumpDialog(tester, photos: copies(1));

    expect(find.text('Move 1 photo to Trash?'), findsOneWidget);
  });

  testBothViewports('a long list scrolls and keeps its buttons', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpDialog(tester, size: size, photos: copies(80), events: events);

    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('duplicates_delete_cancel')));
    await tester.tap(find.byKey(const ValueKey('duplicates_delete_confirm')));
    await tester.pump();

    expect(events, ['cancel', 'confirm']);
  });
}
