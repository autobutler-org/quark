import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart';

/// #2576: the Photos library names its way into Duplicates on screen — a
/// "Duplicates" chip on a wide screen, a "Tools" menu on a phone — instead of
/// a copy icon in the top row whose name only a hover could reveal.
void main() {
  Future<void> pumpPhotos(WidgetTester tester, Size size) async {
    setViewport(tester, size);
    await tester.pumpWidget(const MaterialApp(home: PhotosPage()));
    await tester.pump();
  }

  testWidgets('a wide library shows a Duplicates chip in its second row', (
    tester,
  ) async {
    await pumpPhotos(tester, wideViewport);

    expect(tester.takeException(), isNull);
    final row = find.byType(QuarkAppBarBottom);
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('photos_duplicates')),
        matching: find.text('Duplicates'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a phone library keeps Duplicates behind a labeled menu', (
    tester,
  ) async {
    await pumpPhotos(tester, narrowViewport);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('photos_duplicates')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('app_bar_bottom_menu')),
        matching: find.text('Tools'),
      ),
      findsOneWidget,
    );
  });

  // #2059: Photos had no search control at all.
  for (final (name, size) in [
    ('wide', wideViewport),
    ('phone', narrowViewport),
  ]) {
    testWidgets('a $name library opens and closes a search by name', (
      tester,
    ) async {
      // A desktop has no device photos to ask for, so the first load ends.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await pumpPhotos(tester, size);
      await tester.pump();
      expect(find.byKey(const ValueKey('photos_search_field')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('photos_search')));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byKey(const ValueKey('photos_search_field')), findsOneWidget);

      // No Quark is chosen here, so nothing is loaded and nothing can
      // match: the grid says so in search's own words, not "No photos yet".
      await tester.enterText(
        find.byKey(const ValueKey('photos_search_field')),
        'beach',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('No photos match "beach"'), findsOneWidget);
      expect(find.text('Search looks at file names.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('photos_search_close')));
      await tester.pump();

      expect(find.byKey(const ValueKey('photos_search_field')), findsNothing);
      expect(find.text('No photos match "beach"'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a $name sample library narrows to the name typed', (
      tester,
    ) async {
      AppSettings.instance.demoMode.value = true;
      addTearDown(() => AppSettings.instance.demoMode.value = false);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await pumpPhotos(tester, size);
      await tester.pump();
      expect(find.byType(PhotoGridTile), findsAtLeast(2));

      await tester.tap(find.byKey(const ValueKey('photos_search')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('photos_search_field')),
        'BEACH',
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PhotoGridTile), findsOneWidget);

      // Escape leaves the search and brings the library back.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('photos_search_field')), findsNothing);
      expect(find.byType(PhotoGridTile), findsAtLeast(2));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
