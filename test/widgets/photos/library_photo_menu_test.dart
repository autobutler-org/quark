import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/photos/library_photo_menu.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #2276: a photo in the library has a menu from its button and a
/// right-click, while a long press still selects it.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);
  const actions = [
    'add_to_album',
    'favorite',
    'download',
    'share',
    'copy',
    'duplicate',
    'delete',
  ];
  Finder action(String id) => find.byKey(ValueKey('library_photo_action_$id'));

  Future<void> pumpTile(
    WidgetTester tester, {
    required Size size,
    required List<String> events,
    bool isFavorite = false,
    String? copyUnavailableReason,
    bool heic = false,
    bool video = false,
  }) async {
    setViewport(tester, size);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: SizedBox.square(
                dimension: 120,
                child: PhotoGridTile(
                  item: PhotoItem(
                    id: 'p1',
                    name: 'beach.jpg',
                    isFavorite: isFavorite,
                  ),
                  thumbnailBuilder: (context, photo) =>
                      const ColoredBox(color: Colors.teal),
                  onTap: () => events.add('tap'),
                  onLongPress: () => events.add('select'),
                  longPressOpensMenu: false,
                  onMenu: (position) => LibraryPhotoMenu(
                    isFavorite: isFavorite,
                    onAddToAlbum: () => events.add('add_to_album'),
                    onToggleFavorite: () => events.add('favorite'),
                    onDownload: () => events.add('download'),
                    onShare: () => events.add('share'),
                    onCopy: video ? null : () => events.add('copy'),
                    copyUnavailableReason: copyUnavailableReason,
                    onDuplicate: video ? null : () => events.add('duplicate'),
                    onDelete: () => events.add('delete'),
                    onDownloadAsJpeg: heic
                        ? () => events.add('download_jpeg')
                        : null,
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

    testWidgets('every action is offered and runs its own ($label)', (
      tester,
    ) async {
      for (final id in actions) {
        final events = <String>[];
        await pumpTile(tester, size: size, events: events);

        await tester.tap(find.byKey(const ValueKey('photo_tile_menu_p1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final other in actions) {
          expect(action(other), findsOneWidget, reason: other);
        }

        await tester.tap(action(id));
        await tester.pumpAndSettle();
        expect(events, [id]);
      }
    });

    testWidgets('a right-click opens the same menu ($label)', (tester) async {
      final events = <String>[];
      await pumpTile(tester, size: size, events: events);

      await tester.tap(
        find.byKey(const ValueKey('photo_tile_p1')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      for (final id in actions) {
        expect(action(id), findsOneWidget, reason: id);
      }
    });

    testWidgets('a long press still selects ($label)', (tester) async {
      final events = <String>[];
      await pumpTile(tester, size: size, events: events);

      await tester.longPress(find.byKey(const ValueKey('photo_tile_p1')));
      await tester.pumpAndSettle();

      expect(events, ['select']);
      expect(action('download'), findsNothing);
    });
  }

  testWidgets('a video leaves out Copy and Duplicate (#3428)', (tester) async {
    final events = <String>[];
    await pumpTile(tester, size: wideViewport, events: events, video: true);

    await tester.tap(find.byKey(const ValueKey('photo_tile_menu_p1')));
    await tester.pumpAndSettle();

    expect(action('copy'), findsNothing);
    expect(action('duplicate'), findsNothing);
    for (final id in ['add_to_album', 'favorite', 'download', 'delete']) {
      expect(action(id), findsOneWidget, reason: id);
    }
  });

  testWidgets('a favorite offers Unfavorite', (tester) async {
    await pumpTile(
      tester,
      size: wideViewport,
      events: <String>[],
      isFavorite: true,
    );

    await tester.tap(find.byKey(const ValueKey('photo_tile_menu_p1')));
    await tester.pumpAndSettle();

    expect(find.text('Unfavorite'), findsOneWidget);
    expect(find.text('Favorite'), findsNothing);
  });

  testWidgets('Copy and Duplicate read differently (#3436)', (tester) async {
    await pumpTile(tester, size: wideViewport, events: <String>[]);

    await tester.tap(find.byKey(const ValueKey('photo_tile_menu_p1')));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Make a copy'), findsNothing);
  });

  testWidgets('Copy is disabled where the clipboard takes no image (#3436)', (
    tester,
  ) async {
    final events = <String>[];
    await pumpTile(
      tester,
      size: wideViewport,
      events: events,
      copyUnavailableReason: 'Clipboard unavailable — use HTTPS to enable',
    );

    await tester.tap(find.byKey(const ValueKey('photo_tile_menu_p1')));
    await tester.pumpAndSettle();
    await tester.tap(action('copy'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(events, isEmpty);
  });

  testWidgets('a HEIC photo also offers Download as JPEG (#4188)', (
    tester,
  ) async {
    final events = <String>[];
    await pumpTile(tester, size: narrowViewport, events: events, heic: true);

    await tester.tap(find.byKey(const ValueKey('photo_tile_menu_p1')));
    await tester.pumpAndSettle();
    expect(find.text('Download as JPEG'), findsOneWidget);
    await tester.tap(action('download_jpeg'));
    await tester.pumpAndSettle();

    expect(events, ['download_jpeg']);
  });

  testWidgets('any other photo does not (#4188)', (tester) async {
    await pumpTile(tester, size: narrowViewport, events: <String>[]);

    await tester.tap(find.byKey(const ValueKey('photo_tile_menu_p1')));
    await tester.pumpAndSettle();

    expect(action('download_jpeg'), findsNothing);
  });
}
