import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/photos/album_actions_menu.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2267: an album's menu opens at the pointer, like every other item's, from
/// its button, a long press and a right-click alike.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);
  const album = AlbumItem(id: 7, name: 'Trips');

  final rename = find.byKey(const ValueKey('album_action_rename'));
  final subAlbum = find.byKey(const ValueKey('album_action_new_sub_album'));
  final delete = find.byKey(const ValueKey('album_action_delete'));

  /// A tile wired the way the photos page wires a user album.
  Future<void> pumpTile(
    WidgetTester tester, {
    required Size size,
    required List<String> events,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 260,
                child: AlbumTreeTile(
                  album: album,
                  selectedAlbumId: null,
                  expandedIds: const {},
                  onSelected: (_) => events.add('select'),
                  onToggleExpanded: (_) {},
                  onMenu: (a, position) => AlbumActionsMenu(
                    onRename: () => events.add('rename'),
                    onCreateSubAlbum: () => events.add('sub'),
                    onDelete: () => events.add('delete'),
                  ).showAt(context, position),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('the button offers every action and runs one ($label)', (
      tester,
    ) async {
      final events = <String>[];
      await pumpTile(tester, size: size, events: events);

      await tester.tap(find.byKey(const ValueKey('album_menu_7')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(rename, findsOneWidget);
      expect(subAlbum, findsOneWidget);
      expect(delete, findsOneWidget);
      // A menu next to the album, not a sheet along the bottom edge.
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(delete);
      await tester.pumpAndSettle();

      expect(events, ['delete']);
      expect(rename, findsNothing);
    });

    testWidgets('a right-click opens it at the pointer ($label)', (
      tester,
    ) async {
      final events = <String>[];
      await pumpTile(tester, size: size, events: events);
      final row = tester.getCenter(find.byKey(const ValueKey('album_tile_7')));

      await tester.tapAt(row, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      // Vertically at the click; a narrow screen may slide it sideways to fit.
      expect(tester.getRect(rename).top, closeTo(row.dy, 24));
      await tester.tap(rename);
      await tester.pumpAndSettle();
      expect(events, ['rename']);
    });

    testWidgets('a long press opens it too, without selecting ($label)', (
      tester,
    ) async {
      final events = <String>[];
      await pumpTile(tester, size: size, events: events);

      await tester.longPress(find.byKey(const ValueKey('album_tile_7')));
      await tester.pumpAndSettle();
      await tester.tap(subAlbum);
      await tester.pumpAndSettle();

      expect(events, ['sub']);
    });
  }
}
