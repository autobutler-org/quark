// Left-handed mode (#1812): one scope above the pages, and the bar and the
// page shell mirror their navigation controls under it.
//
// The cases that matter are the ones a thumb meets: which edge the brand
// button, the drawer and the floating button are on, and that the brand
// button still opens the drawer once the drawer has changed sides.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const brand = ValueKey('brand_button');
  const refresh = ValueKey('refresh_button');
  const action = ValueKey('page_action');
  const fab = ValueKey('page_fab');

  Widget page({required bool leftHanded, Widget? middle}) => QuarkHandedness(
    leftHanded: leftHanded,
    child: QuarkPageScaffold(
      title: 'Photos',
      icon: QuarkIcons.photo_library_outlined,
      appBar: middle == null
          ? null
          : QuarkAppBar(
              label: 'Photos',
              icon: QuarkIcons.photo_library_outlined,
              onRefresh: () {},
              middle: middle,
              actions: [
                QuarkBarIconButton(
                  key: action,
                  icon: QuarkIcons.search,
                  tooltip: 'Search',
                  onPressed: () {},
                ),
              ],
            ),
      onRefresh: () {},
      actions: [
        QuarkBarIconButton(
          key: action,
          icon: QuarkIcons.search,
          tooltip: 'Search',
          onPressed: () {},
        ),
      ],
      drawer: const Drawer(child: Text('navigation')),
      floatingActionButton: FloatingActionButton(
        key: fab,
        tooltip: 'Create',
        onPressed: () {},
        child: const Icon(QuarkIcons.add),
      ),
      body: const Text('the grid'),
    ),
  );

  double centerX(WidgetTester tester, Key key) =>
      tester.getCenter(find.byKey(key)).dx;

  testWidgets('without a scope nothing is left-handed', (tester) async {
    late bool leftHanded;
    await pumpAt(
      tester,
      Builder(
        builder: (context) {
          leftHanded = QuarkHandedness.isLeftHanded(context);
          return const SizedBox.shrink();
        },
      ),
    );

    expect(leftHanded, isFalse);
  });

  testBothViewports('right-handed keeps the brand button on the left', (
    tester,
    size,
  ) async {
    await pumpAt(tester, page(leftHanded: false), size: size, scaffold: false);

    expect(centerX(tester, brand), lessThan(centerX(tester, refresh)));
    expect(centerX(tester, refresh), lessThan(centerX(tester, action)));
    expect(centerX(tester, fab), greaterThan(size.width / 2));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).endDrawer, isNull);
  });

  testBothViewports('left-handed mirrors the bar and the floating button', (
    tester,
    size,
  ) async {
    await pumpAt(tester, page(leftHanded: true), size: size, scaffold: false);

    // The brand button is against the right edge, the refresh inside it, the
    // actions against the left.
    expect(
      tester.getTopRight(find.byKey(brand)).dx,
      greaterThan(size.width - 24),
    );
    expect(centerX(tester, refresh), lessThan(centerX(tester, brand)));
    expect(centerX(tester, action), lessThan(centerX(tester, refresh)));
    expect(centerX(tester, action), lessThan(size.width / 2));
    expect(centerX(tester, fab), lessThan(size.width / 2));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('left-handed opens the drawer from the right', (
    tester,
    size,
  ) async {
    await pumpAt(tester, page(leftHanded: true), size: size, scaffold: false);

    expect(find.text('navigation'), findsNothing);

    await tester.tap(find.byKey(brand));
    await tester.pumpAndSettle();

    expect(find.text('navigation'), findsOneWidget);
    expect(tester.getTopRight(find.byType(Drawer)).dx, size.width);
  });

  testBothViewports('left-handed opens the drawer on a swipe from the right', (
    tester,
    size,
  ) async {
    await pumpAt(tester, page(leftHanded: true), size: size, scaffold: false);

    await tester.dragFrom(
      Offset(size.width - 4, size.height / 2),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('navigation'), findsOneWidget);
  });

  testBothViewports('right-handed opens the drawer from the left', (
    tester,
    size,
  ) async {
    await pumpAt(tester, page(leftHanded: false), size: size, scaffold: false);

    await tester.tap(find.byKey(brand));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byType(Drawer)).dx, 0);
  });

  testBothViewports('left-handed puts a middle between brand and actions', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      page(leftHanded: true, middle: const Text('breadcrumbs')),
      size: size,
      scaffold: false,
    );

    final middle = tester.getCenter(find.text('breadcrumbs')).dx;
    expect(centerX(tester, action), lessThan(middle));
    expect(middle, lessThan(centerX(tester, refresh)));
    expect(centerX(tester, refresh), lessThan(centerX(tester, brand)));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('left-handed keeps what is in a slot reading the same', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      page(leftHanded: true, middle: const Text('breadcrumbs')),
      size: size,
      scaffold: false,
    );

    // Only the order of the slots flips: the brand badge still leads its
    // label, and a page's middle is not handed a right-to-left layout.
    for (final finder in [find.text('Photos'), find.text('breadcrumbs')]) {
      expect(
        Directionality.of(tester.element(finder)),
        TextDirection.ltr,
        reason: '$finder',
      );
    }
  });

  testWidgets('the page mirrors when the scope flips', (tester) async {
    await pumpAt(tester, page(leftHanded: false), scaffold: false);
    expect(centerX(tester, brand), lessThan(wideViewport.width / 2));

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: page(leftHanded: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(centerX(tester, brand), greaterThan(wideViewport.width / 2));
  });
}
