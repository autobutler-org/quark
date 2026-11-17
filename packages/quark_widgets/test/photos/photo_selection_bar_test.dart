import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testWidgets('counts the selection and adds it to an album', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      PhotoSelectionBar(
        selectedCount: 3,
        onAddToAlbum: () => events.add('add'),
      ),
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

  testWidgets('refuses to open the picker with nothing selected', (
    tester,
  ) async {
    var adds = 0;
    await pumpAt(
      tester,
      PhotoSelectionBar(selectedCount: 0, onAddToAlbum: () => adds++),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('photo_selection_add_to_album')),
    );
    expect(button.onPressed, isNull);
    expect(adds, 0);
  });

  group('actions on the selection (#4154)', () {
    const keys = [
      'photo_selection_favorite',
      'photo_selection_download',
      'photo_selection_share',
      'photo_selection_copy',
      'photo_selection_remove_from_album',
      'photo_selection_delete',
    ];

    PhotoSelectionBar bar(
      List<String> events, {
      int count = 3,
      bool allFavorites = false,
      String? reason,
    }) => PhotoSelectionBar(
      selectedCount: count,
      onAddToAlbum: () => events.add('add'),
      allFavorites: allFavorites,
      onFavorite: () => events.add('favorite'),
      onDownload: () => events.add('download'),
      onShare: () => events.add('share'),
      onCopy: () => events.add('copy'),
      onRemoveFromAlbum: () => events.add('remove'),
      onDelete: () => events.add('delete'),
      quarkOnlyDisabledReason: reason,
    );

    /// Taps the action keyed [key], through the More menu on a narrow bar.
    Future<void> tapAction(WidgetTester tester, String key) async {
      final more = find.byKey(const ValueKey('photo_selection_more'));
      if (more.evaluate().isNotEmpty) {
        await tester.tap(more);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    testBothViewports('every action reaches its callback', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpAt(tester, bar(events), size: size);

      for (final key in keys) {
        await tapAction(tester, key);
      }

      expect(events, [
        'favorite',
        'download',
        'share',
        'copy',
        'remove',
        'delete',
      ]);
      expect(tester.takeException(), isNull);
    });

    testBothViewports('a phone keeps the count and Add to album in the row '
        'and the rest under More', (tester, size) async {
      await pumpAt(tester, bar([]), size: size);

      expect(find.text('3 photos selected'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('photo_selection_add_to_album')),
        findsOneWidget,
      );
      final narrow = size == narrowViewport;
      expect(
        find.byKey(const ValueKey('photo_selection_more')),
        narrow ? findsOneWidget : findsNothing,
      );
      for (final key in keys) {
        expect(
          find.byKey(ValueKey(key)),
          narrow ? findsNothing : findsOneWidget,
        );
      }
      if (narrow) expect(find.text('More'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testBothViewports('reads Unfavorite when every photo is a favorite', (
      tester,
      size,
    ) async {
      await pumpAt(tester, bar([], allFavorites: true), size: size);
      final more = find.byKey(const ValueKey('photo_selection_more'));
      if (more.evaluate().isNotEmpty) {
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(find.text('Unfavorite'), findsOneWidget);
      } else {
        expect(
          tester
              .widget<QuarkBarIconButton>(
                find.byKey(const ValueKey('photo_selection_favorite')),
              )
              .tooltip,
          'Unfavorite',
        );
      }
    });

    testBothViewports('Download is labeled and downloads the selection once '
        '(#4195)', (tester, size) async {
      final events = <String>[];
      await pumpAt(
        tester,
        PhotoSelectionBar(
          selectedCount: 12,
          onAddToAlbum: () => events.add('add'),
          onDownload: () => events.add('download'),
        ),
        size: size,
      );

      if (size == wideViewport) {
        expect(
          tester
              .widget<QuarkBarIconButton>(
                find.byKey(const ValueKey('photo_selection_download')),
              )
              .tooltip,
          'Download',
        );
      } else {
        // A phone keeps it under More.
        await tester.tap(find.byKey(const ValueKey('photo_selection_more')));
        await tester.pumpAndSettle();
        expect(find.text('Download'), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('photo_selection_download')));
      await tester.pumpAndSettle();

      expect(events, ['download']);
      expect(tester.takeException(), isNull);
    });

    testBothViewports('a device photo in the selection turns the Quark '
        'actions off and says why', (tester, size) async {
      final events = <String>[];
      const why = "Photos on this phone can't be changed on your Quark";
      await pumpAt(tester, bar(events, reason: why), size: size);

      if (size == narrowViewport) {
        final more = tester.widget<QuarkBarMenuButton>(
          find.byType(QuarkBarMenuButton),
        );
        expect(more.enabled, isFalse);
        expect(more.tooltip, why);
      } else {
        for (final key in keys) {
          final button = tester.widget<QuarkBarIconButton>(
            find.byKey(ValueKey(key)),
          );
          expect(button.onPressed, isNull, reason: key);
          expect(button.tooltip, why);
        }
      }
      // Add to album says what it skipped, so it stays on.
      await tester.tap(
        find.byKey(const ValueKey('photo_selection_add_to_album')),
      );
      expect(events, ['add']);
    });

    testWidgets('a null callback leaves its action out', (tester) async {
      await pumpAt(
        tester,
        PhotoSelectionBar(
          selectedCount: 2,
          onAddToAlbum: () {},
          onDelete: () {},
          onRemoveFromAlbum: () {},
          removeFromAlbumLabel: 'Remove from favorites',
        ),
      );

      expect(find.byKey(const ValueKey('photo_selection_share')), findsNothing);
      expect(
        tester
            .widget<QuarkBarIconButton>(
              find.byKey(const ValueKey('photo_selection_remove_from_album')),
            )
            .tooltip,
        'Remove from favorites',
      );
    });
  });
}
