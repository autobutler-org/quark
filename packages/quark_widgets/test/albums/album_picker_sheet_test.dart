import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    int selectedCount = 2,
    List<AlbumItem> albums = _albums,
    bool isLoading = false,
    String? error,
    List<String>? events,
  }) {
    return pumpAt(
      tester,
      AlbumPickerSheet(
        selectedCount: selectedCount,
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
    expect(find.text('Add 2 photos to...'), findsOneWidget);
    expect(find.text('Iceland'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('album_picker_2')));
    expect(events, ['pick:2']);
  });

  testBothViewports('says "photo" for exactly one', (tester, size) async {
    await pumpSheet(tester, size: size, selectedCount: 1);

    expect(find.text('Add 1 photo to...'), findsOneWidget);
  });

  testBothViewports('shows a spinner while loading', (tester, size) async {
    await pumpSheet(tester, size: size, isLoading: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
    await pumpAt(
      tester,
      AlbumPickerSheet(
        selectedCount: 4,
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
  /// they are still in.
  testBothViewports('the sheet closes with Close, not a second Cancel', (
    tester,
    size,
  ) async {
    var closes = 0;
    await pumpAt(
      tester,
      AlbumPickerSheet(
        selectedCount: 3,
        albums: const [AlbumItem(id: 1, name: 'Trips')],
        onPicked: (_) {},
        onRetry: () {},
        onClose: () => closes++,
      ),
      size: size,
    );

    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('album_picker_close')));
    await tester.pump();

    expect(closes, 1);
  });

  testWidgets('a sheet with no close handler shows no button', (tester) async {
    await pumpAt(
      tester,
      AlbumPickerSheet(
        selectedCount: 1,
        albums: const [AlbumItem(id: 1, name: 'Trips')],
        onPicked: (_) {},
        onRetry: () {},
      ),
      size: narrowViewport,
    );

    expect(find.byKey(const ValueKey('album_picker_close')), findsNothing);
  });
}
