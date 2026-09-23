import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Widget page({
    List<Widget> actions = const [],
    VoidCallback? onRefresh,
    bool isRefreshing = false,
    String label = 'Photos',
  }) => Scaffold(
    appBar: QuarkAppBar(
      label: label,
      icon: QuarkIcons.photo_library_outlined,
      actions: actions,
      onRefresh: onRefresh,
      isRefreshing: isRefreshing,
    ),
    drawer: const QuarkDrawer(activeSection: QuarkDrawerSection.photos),
    body: const SizedBox.shrink(),
  );

  Finder refreshButton() => find.byKey(const ValueKey('refresh_button'));

  testBothViewports('leads with the brand button and no title', (
    tester,
    size,
  ) async {
    await pumpAt(tester, page(), size: size, scaffold: false);

    expect(find.byType(QuarkBrandButton), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
  });

  testBothViewports('opens the drawer from the brand button', (
    tester,
    size,
  ) async {
    await pumpAt(tester, page(), size: size, scaffold: false);

    await tester.tap(find.byKey(const ValueKey('brand_button')));
    await tester.pumpAndSettle();

    expect(find.byType(QuarkDrawer), findsOneWidget);
  });

  testBothViewports('renders the actions it is given, in order', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      page(actions: const [Text('first'), Text('second')]),
      size: size,
      scaffold: false,
    );

    expect(
      tester.getRect(find.text('first')).left,
      lessThan(tester.getRect(find.text('second')).left),
    );
  });

  testWidgets('reserves enough leading width for the brand button', (
    tester,
  ) async {
    await pumpAt(tester, page(), size: narrowViewport, scaffold: false);

    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(
      bar.leadingWidth,
      greaterThanOrEqualTo(QuarkBrandButton.preferredWidth),
    );
    expect(tester.takeException(), isNull);
  });

  // #2254: refresh is a slot beside the brand button, not an action. Every
  // page used to put it at a different index on the right.
  testBothViewports('leaves the refresh slot out when onRefresh is null', (
    tester,
    size,
  ) async {
    await pumpAt(tester, page(), size: size, scaffold: false);

    expect(refreshButton(), findsNothing);
  });

  testBothViewports('sits between the brand button and the actions', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      page(onRefresh: () {}, actions: const [Text('an action')]),
      size: size,
      scaffold: false,
    );

    final brand = tester.getRect(find.byKey(const ValueKey('brand_button')));
    final refresh = tester.getRect(refreshButton());
    expect(refresh.left, greaterThanOrEqualTo(brand.right));
    expect(
      refresh.right,
      lessThanOrEqualTo(tester.getRect(find.text('an action')).left),
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('refreshes on tap', (tester, size) async {
    var refreshes = 0;
    await pumpAt(
      tester,
      page(onRefresh: () => refreshes++),
      size: size,
      scaffold: false,
    );

    await tester.tap(refreshButton());
    await tester.pump();

    expect(refreshes, 1);
  });

  testBothViewports('spins and refuses taps while refreshing', (
    tester,
    size,
  ) async {
    var refreshes = 0;
    await pumpAt(
      tester,
      page(onRefresh: () => refreshes++, isRefreshing: true),
      size: size,
      scaffold: false,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: refreshButton(),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(refreshButton(), warnIfMissed: false);
    await tester.pump();

    expect(refreshes, 0);
  });

  testWidgets('the refresh slot fits beside the brand button at 360px', (
    tester,
  ) async {
    await pumpAt(
      tester,
      page(label: 'Photos ' * 20, onRefresh: () {}),
      size: narrowViewport,
      scaffold: false,
    );

    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(
      bar.leadingWidth,
      greaterThan(QuarkBrandButton.preferredWidth),
      reason: 'the slot needs its own width, or the brand button is clipped',
    );
    expect(bar.leadingWidth, lessThan(narrowViewport.width));
    expect(tester.takeException(), isNull);
  });

  // #2311: the theme toggle, refresh and the jobs badge each picked up a
  // different icon size depending on whether they sat in an AppBar or a Row.
  testBothViewports('renders every action at one glyph size', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkAppBarTrailing(
        actions: [JobsBadge(runningCount: 2, onTap: () {})],
        child: page(
          onRefresh: () {},
          actions: [
            QuarkBarIconButton(
              key: const ValueKey('select'),
              icon: QuarkIcons.check_circle_outline,
              tooltip: 'Select',
              onPressed: () {},
            ),
            ThemeToggleButton(mode: ThemeMode.dark, onChanged: (_) {}),
          ],
        ),
      ),
      size: size,
      scaffold: false,
    );

    for (final key in const [
      'refresh_button',
      'select',
      'theme_toggle',
      'jobs_badge',
    ]) {
      final button = find.byKey(ValueKey(key));
      expect(
        tester.getSize(button),
        const Size.square(QuarkBarIconButton.size),
        reason: key,
      );
      final glyph = tester.widget<RichText>(
        find.descendant(of: button, matching: find.byType(RichText)).first,
      );
      expect(
        glyph.text.style!.fontSize,
        QuarkBarIconButton.glyphSize,
        reason: key,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws a hairline under the bar', (tester) async {
    await pumpAt(tester, page(), size: narrowViewport, scaffold: false);

    final shape = tester.widget<AppBar>(find.byType(AppBar)).shape! as Border;
    expect(shape.bottom.color, QuarkTokens.dark.border);
  });

  testBothViewports('fills the space between with its middle', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Scaffold(
        appBar: QuarkAppBar(
          label: 'Files',
          icon: QuarkIcons.folder_outlined,
          onRefresh: () {},
          middle: const SizedBox(
            key: ValueKey('middle'),
            height: 36,
            width: double.infinity,
          ),
          actions: const [Text('an action')],
        ),
        body: const SizedBox.shrink(),
      ),
      size: size,
      scaffold: false,
    );

    final middle = tester.getRect(find.byKey(const ValueKey('middle')));
    expect(
      middle.left,
      greaterThanOrEqualTo(tester.getRect(refreshButton()).right),
    );
    expect(
      middle.right,
      lessThanOrEqualTo(tester.getRect(find.text('an action')).left),
    );
    expect(tester.takeException(), isNull);
  });
}
