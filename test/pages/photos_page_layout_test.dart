import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark_widgets/quark_widgets.dart';

// The photos view rendered nothing below 900px: the compact branch puts the
// sidebar in a SliverToBoxAdapter, which hands its child unbounded height, and
// the sidebar ended in an `Expanded`. That combination throws during
// performLayout, so the subtree never lays out — a red box in debug and a blank
// screen in release, where assertions are stripped (#1599).
//
// These pump the real page. No backend, no photos, no device — it is pure
// layout, which is what makes it embarrassing that it shipped.
void main() {
  const compactSize = Size(390, 844); // iPhone-ish
  const desktopSize = Size(1400, 900);

  Future<PhotosPageState> pumpPhotos(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PhotosPage()));
    await tester.pump();
    return tester.state<PhotosPageState>(find.byType(PhotosPage));
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
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(AlbumSidebar), findsOneWidget);
    });

    testWidgets('desktop (>=900px) still lays out', (tester) async {
      await pumpPhotos(tester, desktopSize);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlbumSidebar), findsOneWidget);
    });

    // The window can cross the breakpoint at runtime; both directions have to
    // survive it, since the sidebar swaps between Expanded and shrink-wrapped.
    testWidgets('resizing across the 900px breakpoint keeps laying out', (
      tester,
    ) async {
      await pumpPhotos(tester, desktopSize);
      expect(tester.takeException(), isNull);

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

  // The same Expanded-in-a-Column bug lived one level down in the album
  // sidebar. It is a package widget now, and its narrow and wide layouts,
  // shrink-wrapped under a sliver and filling a bounded pane, are covered in
  // packages/quark_widgets/test/albums/album_sidebar_test.dart.

  // _measureAndJumpNav re-posted itself every frame until the nav panel
  // reported a size. Every failure path re-posted unconditionally, so it was an
  // unbounded frame loop: forever on desktop, where no nav panel is ever built,
  // and forever in compact mode while the layout error stopped it getting a
  // size. Nothing checked `mounted`, so the chain outlived the State.
  group('nav measurement terminates', () {
    testWidgets('compact settles after the layout succeeds', (tester) async {
      final state = await pumpPhotos(tester, compactSize);

      for (var i = 0; i < 30 && !state.navScrollSettled; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        state.navScrollSettled,
        isTrue,
        reason: 'the nav measurement must stop scheduling frames',
      );
      expect(
        state.navMeasureAttempts,
        lessThan(20),
        reason: 'it should measure promptly, not exhaust its retry budget',
      );
    });

    testWidgets('desktop never starts measuring — there is no nav panel', (
      tester,
    ) async {
      final state = await pumpPhotos(tester, desktopSize);

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        state.navMeasureAttempts,
        0,
        reason: 'desktop builds no nav panel, so it must not retry at all',
      );
    });

    // The bound is the backstop: even if the panel never reports a size, the
    // retries have to stop rather than burn frames for the life of the process.
    testWidgets('gives up rather than looping when a size never arrives', (
      tester,
    ) async {
      final state = await pumpPhotos(tester, compactSize);

      for (var i = 0; i < 40 && !state.navScrollSettled; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(state.navScrollSettled, isTrue);
      expect(state.navMeasureAttempts, lessThanOrEqualTo(20));
    });

    testWidgets('disposing the page stops the retry chain', (tester) async {
      await pumpPhotos(tester, compactSize);

      // Replace the page; any outstanding callback must not touch a dead State.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.takeException(), isNull);
    });
  });
}
