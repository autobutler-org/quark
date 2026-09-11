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

    expect(find.text('No albums — create one first'), findsOneWidget);
  });
}
