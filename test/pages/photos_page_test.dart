import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart';

/// The Photos page's search, on a wide screen and a phone.
void main() {
  Future<void> pumpPhotos(WidgetTester tester, Size size) async {
    setViewport(tester, size);
    await tester.pumpWidget(const MaterialApp(home: PhotosPage()));
    await tester.pump();
  }

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

    // #3363: the page's own Focus held the focus, so the field's autofocus
    // was ignored and the first keys typed after opening search were lost.
    testWidgets('a $name search keeps every key typed straight away', (
      tester,
    ) async {
      AppSettings.instance.demoMode.value = true;
      addTearDown(() => AppSettings.instance.demoMode.value = false);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await pumpPhotos(tester, size);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('photos_search')));
      await tester.pump();
      await tester.pump();

      final editable = find.descendant(
        of: find.byKey(const ValueKey('photos_search_field')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

      // Typed into whatever has the keyboard, the way a person types, not
      // through enterText, which focuses the field itself first.
      for (var i = 1; i <= 'beach'.length; i++) {
        final text = 'beach'.substring(0, i);
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
      expect(tester.widget<EditableText>(editable).controller.text, 'beach');
      expect(find.byType(PhotoGridTile), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
