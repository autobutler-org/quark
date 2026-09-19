import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _albums = [
  AlbumItem(
    id: 1,
    name: 'Trips',
    children: [AlbumItem(id: 2, name: 'Iceland', parentId: 1)],
  ),
];

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    Size size = wideViewport,
    List<AlbumItem> albums = _albums,
    bool isLoading = false,
    List<String>? events,
  }) {
    return pumpAt(
      tester,
      AddToAlbumSheet(
        albums: albums,
        memberAlbumIds: const {2},
        isLoading: isLoading,
        onToggle: (a) => events?.add('toggle:${a.id}'),
      ),
      size: size,
    );
  }

  testBothViewports('checks member albums and reports toggles', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpSheet(tester, size: size, events: events);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(QuarkIcons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(QuarkIcons.photo_album_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_to_album_1')));
    await tester.tap(find.byKey(const ValueKey('add_to_album_2')));
    expect(events, ['toggle:1', 'toggle:2']);
  });

  testBothViewports('shows a spinner while loading', (tester, size) async {
    await pumpSheet(tester, size: size, isLoading: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testBothViewports('says so when there are no albums', (tester, size) async {
    await pumpSheet(tester, size: size, albums: const []);

    expect(find.text('No albums yet'), findsOneWidget);
  });

  /// #2041: with no albums the sheet read "No albums — create one first" and
  /// offered nothing, so the user had to dismiss it, leave the photo and go
  /// looking for the create action somewhere else.
  testBothViewports('an empty sheet offers to create an album', (
    tester,
    size,
  ) async {
    var creates = 0;
    await pumpAt(
      tester,
      AddToAlbumSheet(
        albums: const [],
        memberAlbumIds: const {},
        onToggle: (_) {},
        onCreateAlbum: () => creates++,
      ),
      size: size,
    );

    expect(find.text('No albums yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add_to_album_create')));
    await tester.pump();

    expect(creates, 1);
  });

  testWidgets('a caller that cannot create albums offers nothing', (
    tester,
  ) async {
    await pumpAt(
      tester,
      AddToAlbumSheet(
        albums: const [],
        memberAlbumIds: const {},
        onToggle: (_) {},
      ),
      size: narrowViewport,
    );

    expect(find.byKey(const ValueKey('add_to_album_create')), findsNothing);
  });
}
