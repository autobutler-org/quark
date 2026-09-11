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

    expect(find.text('No albums — create one in the Photos view'), findsOne);
  });
}
