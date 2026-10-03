import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/photos/photos_bar_bottom.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// #2576: Duplicates is a labeled control on the Photos bar at every width —
/// a chip reading "Duplicates" on a wide screen, a labeled menu on a phone —
/// never an icon whose only name is a hover tooltip.
void main() {
  Future<List<String>> pump(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
  }) async {
    final taps = <String>[];
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            appBar: QuarkAppBar(
              label: 'Photos',
              icon: Icons.photo,
              bottom: PhotosBarBottom(
                title: 'Library',
                onDuplicates: () => taps.add('duplicates'),
              ),
            ),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('a wide screen shows a Duplicates chip with its word', (
    tester,
  ) async {
    final taps = await pump(tester, wideViewport);

    final chip = find.byKey(const ValueKey('photos_duplicates'));
    expect(
      find.descendant(of: chip, matching: find.text('Duplicates')),
      findsOneWidget,
    );
    expect(find.text('Library'), findsOneWidget);
    await expectTapTargetGuidelines(tester);

    await tester.tap(chip);
    expect(taps, ['duplicates']);
  });

  testWidgets('a phone folds Duplicates into a labeled menu', (tester) async {
    final taps = await pump(tester, narrowViewport);

    expect(find.byKey(const ValueKey('photos_duplicates')), findsNothing);
    final menu = find.byKey(const ValueKey('app_bar_bottom_menu'));
    expect(
      find.descendant(of: menu, matching: find.text('Tools')),
      findsOneWidget,
    );
    await expectTapTargetGuidelines(tester);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    final item = find.byKey(const ValueKey('photos_menu_duplicates'));
    expect(
      find.descendant(of: item, matching: find.text('Duplicates')),
      findsOneWidget,
    );
    await expectTapTargetGuidelines(tester);

    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(taps, ['duplicates']);
  });

  for (final size in const [narrowViewport, wideViewport]) {
    testWidgets('lays out at 2.0 text scale at $size', (tester) async {
      await pump(tester, size, textScale: 2);

      expect(tester.takeException(), isNull);
      expect(
        find.text(size == narrowViewport ? 'Tools' : 'Duplicates'),
        findsOneWidget,
      );
    });
  }
}
