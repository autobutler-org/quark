import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/widgets/photos/photos_bar_bottom.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

// The photos view rendered nothing below 900px: the compact branch puts the
// sidebar in a SliverToBoxAdapter, which hands its child unbounded height, and
// the sidebar ended in an `Expanded`. That combination throws during
// performLayout, so the subtree never lays out — a red box in debug and a blank
// screen in release, where assertions are stripped (#1599).
//
// These pump the real page. No backend, no photos, no device — it is pure
// layout, which is what makes it embarrassing that it shipped. A phone no
// longer stacks the sidebar at all (#4149), but the page still crosses the
// breakpoint.
void main() {
  const compactSize = Size(390, 844); // iPhone-ish
  const desktopSize = Size(1400, 900);

  Future<void> pumpPhotos(WidgetTester tester, Size size) async {
    setViewport(tester, size);
    await tester.pumpWidget(const MaterialApp(home: PhotosPage()));
    await tester.pump();
  }

  group('layout', () {
    testWidgets('compact (<900px) lays out without an exception', (
      tester,
    ) async {
      await pumpPhotos(tester, compactSize);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the compact branch must not throw during performLayout',
      );
      // Not just "no exception" — the content has to actually be on screen.
      // The albums are in the Library picker on a phone (#4149).
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('photos_library_picker')),
        findsOneWidget,
      );
    });

    // The window can cross the breakpoint at runtime; both directions have to
    // survive it, since the sidebar swaps between Expanded and shrink-wrapped.
    testWidgets('resizing across the 900px breakpoint keeps laying out', (
      tester,
    ) async {
      await pumpPhotos(tester, desktopSize);
      expect(tester.takeException(), isNull);
      expect(find.byType(AlbumSidebar), findsOneWidget);

      tester.view.physicalSize = compactSize;
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'desktop -> compact must not throw',
      );

      tester.view.physicalSize = desktopSize;
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'compact -> desktop must not throw',
      );
    });
  });

  // Upload and Search sit beside Tools in the library's second row, which
  // leaves the top bar room for the page name on a phone.
  testWidgets('compact: upload and search sit in the library row', (
    tester,
  ) async {
    await pumpPhotos(tester, compactSize);

    for (final key in const ['photos_upload', 'photos_search']) {
      expect(
        find.descendant(
          of: find.byType(PhotosBarBottom),
          matching: find.byKey(ValueKey(key)),
        ),
        findsOneWidget,
        reason: key,
      );
    }
    expect(find.text('Photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // The same Expanded-in-a-Column bug lived one level down in the album
  // sidebar. It is a package widget now, and its narrow and wide layouts,
  // shrink-wrapped under a sliver and filling a bounded pane, are covered in
  // packages/quark_widgets/test/albums/album_sidebar_test.dart.
}
