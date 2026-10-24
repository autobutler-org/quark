import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _albums = [
  AlbumItem(
    id: 1,
    name: 'Trips',
    itemCount: 3,
    children: [AlbumItem(id: 2, name: 'Iceland', parentId: 1)],
  ),
];

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    Size size = wideViewport,
    List<AlbumItem> albums = _albums,
    bool isLoading = false,
    String? error,
    List<String>? events,
  }) {
    return pumpInSheet(
      tester,
      AlbumPickerSheet(
        albums: albums,
        isLoading: isLoading,
        error: error,
        onPicked: (a) => events?.add('pick:${a.id}'),
        onRetry: () => events?.add('retry'),
      ),
      size: size,
    );
  }

  testBothViewports('lists the whole tree and reports the pick', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpSheet(tester, size: size, events: events);

    expect(tester.takeException(), isNull);
    expect(find.text('Iceland'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('album_picker_2')));
    expect(events, ['pick:2']);
  });

  testBothViewports('shows a spinner while loading', (tester, size) async {
    await pumpSheet(tester, size: size, isLoading: true);

    expect(find.byType(QuarkLoader), findsOneWidget);
  });

  testBothViewports('offers a retry under an error', (tester, size) async {
    final events = <String>[];
    await pumpSheet(
      tester,
      size: size,
      error: "Couldn't load your albums.",
      events: events,
    );

    expect(find.text("Couldn't load your albums."), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('album_picker_retry')));
    expect(events, ['retry']);
  });

  testBothViewports('says so when there are no albums', (tester, size) async {
    await pumpSheet(tester, size: size, albums: const []);

    expect(find.text('No albums yet'), findsOne);
  });

  /// #2041, the other sheet: picking an album for a selection with no albums
  /// read "No albums — create one in the Photos view", which meant leaving
  /// the selection behind to go and make one.
  testBothViewports('an empty picker offers to create an album', (
    tester,
    size,
  ) async {
    var creates = 0;
    await pumpInSheet(
      tester,
      AlbumPickerSheet(
        albums: const [],
        onPicked: (_) {},
        onRetry: () {},
        onCreateAlbum: () => creates++,
      ),
      size: size,
    );

    expect(find.text('No albums yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('album_picker_create')));
    await tester.pump();

    expect(creates, 1);
  });

  /// #2060: the selection bar behind this sheet has a Cancel that throws the
  /// selection away. A second button with the same word, dismissing only the
  /// sheet, is how someone ends up believing they backed out of a selection
  /// they are still in. The sheet's own close button says Close.
  testBothViewports('the sheet closes with Close, not a second Cancel', (
    tester,
    size,
  ) async {
    await pumpInSheet(
      tester,
      AlbumPickerSheet(
        albums: const [AlbumItem(id: 1, name: 'Trips')],
        onPicked: (_) {},
        onRetry: () {},
      ),
      size: size,
    );

    expect(find.text('Cancel'), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testBothViewports('checks member albums under its own key prefix', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpInSheet(
      tester,
      AlbumPickerSheet(
        albums: _albums,
        memberAlbumIds: const {2},
        keyPrefix: 'add_to_album',
        onPicked: (a) => events.add('pick:${a.id}'),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(QuarkIcons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(QuarkIcons.photo_album_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_to_album_1')));
    await tester.tap(find.byKey(const ValueKey('add_to_album_2')));
    expect(events, ['pick:1', 'pick:2']);
  });

  testWidgets('an error without onRetry offers no retry', (tester) async {
    await pumpInSheet(
      tester,
      AlbumPickerSheet(
        albums: _albums,
        error: "Couldn't load your albums.",
        onPicked: (_) {},
      ),
      size: narrowViewport,
    );

    expect(find.text("Couldn't load your albums."), findsOneWidget);
    expect(find.byKey(const ValueKey('album_picker_retry')), findsNothing);
  });

  testWidgets('a caller that cannot create albums offers nothing', (
    tester,
  ) async {
    await pumpInSheet(
      tester,
      AlbumPickerSheet(albums: const [], onPicked: (_) {}),
      size: narrowViewport,
    );

    expect(find.byKey(const ValueKey('album_picker_create')), findsNothing);
  });

  testWidgets('renders each album\'s count in agreement with itself', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      albums: const [
        AlbumItem(id: 1, name: 'Trips', itemCount: 1),
        AlbumItem(id: 3, name: 'Pets', itemCount: 4),
      ],
    );

    expect(find.text('1 photo'), findsOneWidget);
    expect(find.text('4 photos'), findsOneWidget);
  });

  /// #2590: a tap adds or removes at once and the sheet stays open, so with
  /// only a close X and the scrim there was no clear way to say "finished".
  testBothViewports('ends with a labeled Done', (tester, size) async {
    var done = 0;
    await pumpInSheet(
      tester,
      AlbumPickerSheet(albums: _albums, onPicked: (_) {}, onDone: () => done++),
      size: size,
    );

    final button = find.byKey(const ValueKey('album_picker_done'));
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: button, matching: find.text('Done')),
      findsOneWidget,
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    expect(done, 1);
  });

  testWidgets('no Done while loading, or without onDone', (tester) async {
    await pumpInSheet(
      tester,
      AlbumPickerSheet(
        albums: _albums,
        onPicked: (_) {},
        onDone: () {},
        isLoading: true,
      ),
      size: narrowViewport,
    );
    expect(find.byKey(const ValueKey('album_picker_done')), findsNothing);

    await pumpSheet(tester, size: narrowViewport);
    expect(find.byKey(const ValueKey('album_picker_done')), findsNothing);
  });
}
