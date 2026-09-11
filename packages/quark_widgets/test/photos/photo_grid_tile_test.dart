import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    Size size = wideViewport,
    PhotoItem item = const PhotoItem(id: 'p1', name: 'beach.jpg'),
    bool isSelected = false,
    bool selectionMode = false,
    List<String>? events,
    bool withDoubleTap = false,
  }) {
    void record(String e) => events?.add(e);
    return pumpAt(
      tester,
      Center(
        child: SizedBox.square(
          dimension: 120,
          child: PhotoGridTile(
            item: item,
            isSelected: isSelected,
            selectionMode: selectionMode,
            thumbnailBuilder: (context, photo) =>
                ColoredBox(color: Colors.teal, child: Text(photo.name)),
            onTap: () => record('tap'),
            onLongPress: () => record('long'),
            onDoubleTap: withDoubleTap ? () => record('double') : null,
          ),
        ),
      ),
      size: size,
    );
  }

  testBothViewports('renders the thumbnail and reports tap and long press', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpTile(tester, size: size, events: events);

    expect(find.text('beach.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('photo_tile_p1')));
    await tester.longPress(find.byKey(const ValueKey('photo_tile_p1')));
    await tester.pump();

    expect(events, ['tap', 'long']);
  });

  testBothViewports('reports a double tap when one is offered', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpTile(tester, size: size, events: events, withDoubleTap: true);

    final tile = find.byKey(const ValueKey('photo_tile_p1'));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(events, ['double']);
  });

  testBothViewports('draws the star and live badge outside selection mode', (
    tester,
    size,
  ) async {
    await pumpTile(
      tester,
      size: size,
      item: const PhotoItem(
        id: 'p1',
        name: 'beach.jpg',
        hasLiveVideo: true,
        isFavorite: true,
      ),
    );

    expect(find.byIcon(QuarkIcons.star_rounded), findsOneWidget);
    expect(find.byType(LiveBadge), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_tile_check_p1')), findsNothing);
  });

  testBothViewports('selection mode hides the star and shows a checkbox', (
    tester,
    size,
  ) async {
    await pumpTile(
      tester,
      size: size,
      selectionMode: true,
      item: const PhotoItem(id: 'p1', name: 'beach.jpg', isFavorite: true),
    );

    expect(find.byIcon(QuarkIcons.star_rounded), findsNothing);
    expect(find.byKey(const ValueKey('photo_tile_check_p1')), findsOneWidget);
    expect(find.byIcon(QuarkIcons.check), findsNothing);
  });

  testBothViewports('a selected tile fills its checkbox', (tester, size) async {
    await pumpTile(tester, size: size, selectionMode: true, isSelected: true);

    expect(find.byIcon(QuarkIcons.check), findsOneWidget);
  });
}
