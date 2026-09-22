import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/photos/album_item_menu.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2260: a photo in an album has a visible menu button that opens the same
/// entries a long press used to, and a system album offers no Remove.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final button = find.byKey(const ValueKey('photo_tile_menu_p1'));
  final add = find.byKey(const ValueKey('album_item_action_add'));
  final unfavorite = find.byKey(const ValueKey('album_item_action_unfavorite'));
  final remove = find.byKey(const ValueKey('album_item_action_remove'));

  /// A tile wired the way the photos page wires an album photo.
  Future<void> pumpTile(
    WidgetTester tester, {
    required Size size,
    required List<String> events,
    bool systemAlbum = false,
    bool favorites = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: SizedBox.square(
                dimension: 120,
                child: PhotoGridTile(
                  item: const PhotoItem(id: 'p1', name: 'beach.jpg'),
                  thumbnailBuilder: (context, photo) =>
                      const ColoredBox(color: Colors.teal),
                  onTap: () => events.add('tap'),
                  onLongPress: () => events.add('long'),
                  onMenu: (position) => AlbumItemMenu(
                    onAddToAnotherAlbum: () => events.add('add'),
                    onRemoveFromFavorites: favorites
                        ? () => events.add('unfavorite')
                        : null,
                    onRemoveFromAlbum: systemAlbum
                        ? null
                        : () => events.add('remove'),
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

    testWidgets('the menu button opens the entries ($label)', (tester) async {
      final events = <String>[];
      await pumpTile(tester, size: size, events: events);

      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(add, findsOneWidget);
      expect(remove, findsOneWidget);
      expect(unfavorite, findsNothing);

      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(events, ['remove']);
      expect(remove, findsNothing);
    });

    testWidgets('a long press opens the same entries ($label)', (tester) async {
      final events = <String>[];
      await pumpTile(tester, size: size, events: events);

      await tester.longPress(find.byKey(const ValueKey('photo_tile_p1')));
      await tester.pumpAndSettle();

      expect(add, findsOneWidget);
      expect(remove, findsOneWidget);
      expect(events, isEmpty);
    });

    testWidgets('a system album offers no Remove ($label)', (tester) async {
      final events = <String>[];
      await pumpTile(
        tester,
        size: size,
        events: events,
        systemAlbum: true,
        favorites: true,
      );

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(add, findsOneWidget);
      expect(unfavorite, findsOneWidget);
      expect(remove, findsNothing);
    });
  }
}
