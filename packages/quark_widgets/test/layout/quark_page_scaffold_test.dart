// The page shell: the app bar, the drawer, the body, and the bottom bar that
// every top-level page used to assemble for itself.
//
// The cases that matter are the swap-in app bar a page in selection mode
// uses, and the bottom bar's inset, since both are the reason the shell
// exists rather than each page writing its own `Scaffold`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('renders the title, the actions, and the body', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        actions: [
          IconButton(
            key: const ValueKey('page_upload'),
            icon: const Icon(Icons.add),
            tooltip: 'Upload',
            onPressed: () {},
          ),
        ],
        body: const Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    expect(find.byType(QuarkAppBar), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.byKey(const ValueKey('page_upload')), findsOneWidget);
    expect(find.text('the grid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('opens the drawer from the brand button', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        drawer: const Drawer(child: Text('navigation')),
        body: const Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    expect(find.text('navigation'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('brand_button')));
    await tester.pumpAndSettle();

    expect(find.text('navigation'), findsOneWidget);
  });

  testBothViewports('leaves the brand button inert when there is no drawer', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        body: Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    await tester.tap(find.byKey(const ValueKey('brand_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no drawer, no error');
    expect(find.byType(Drawer), findsNothing);
  });

  testBothViewports('swaps in the app bar a page hands it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        appBar: AppBar(title: const Text('3 selected')),
        body: const Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    // The page's own bar wins outright: no brand button, no page title.
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.byType(QuarkAppBar), findsNothing);
    expect(find.byKey(const ValueKey('brand_button')), findsNothing);
  });

  testBothViewports('renders the bottom bar inside a safe area', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        bottomBar: const Text('3 photos selected'),
        body: const Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    expect(find.text('3 photos selected'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('3 photos selected'),
        matching: find.byType(SafeArea),
      ),
      findsWidgets,
      reason: 'a bottom bar has to clear the home indicator',
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('leaves the bottom bar out when there is none', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        body: Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the page paints on the token background', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const QuarkPageScaffold(
          title: 'Photos',
          icon: QuarkIcons.photo_library_outlined,
          body: Text('the grid'),
        ),
        brightness: brightness,
        scaffold: false,
      );

      expect(tester.takeException(), isNull);
      expect(
        Theme.of(
          tester.element(find.byType(QuarkPageScaffold)),
        ).scaffoldBackgroundColor,
        tokens.background,
      );
    });
  }

  testWidgets('every icon-only button carries a tooltip', (tester) async {
    await pumpAt(
      tester,
      QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Upload',
            onPressed: () {},
          ),
        ],
        body: const Text('the grid'),
      ),
      scaffold: false,
    );

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
    }
  });

  // #2254: the scaffold hands the refresh slot straight to its default bar,
  // and the page's own bar takes it over wholesale when there is one.
  testBothViewports('passes the refresh slot to the default app bar', (
    tester,
    size,
  ) async {
    var refreshes = 0;
    await pumpAt(
      tester,
      QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        onRefresh: () => refreshes++,
        actions: const [Text('an action')],
        body: const Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    final refresh = find.byKey(const ValueKey('refresh_button'));
    expect(refresh, findsOneWidget);
    expect(
      tester.getRect(refresh).left,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('brand_button'))).right,
      ),
    );
    expect(
      tester.getRect(refresh).right,
      lessThanOrEqualTo(tester.getRect(find.text('an action')).left),
    );

    await tester.tap(refresh);
    await tester.pump();
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('shows the spinner while the refresh runs', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        onRefresh: () {},
        isRefreshing: true,
        body: const Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('refresh_button')))
          .onPressed,
      isNull,
    );
  });

  testBothViewports('has no refresh button without onRefresh', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        body: Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    expect(find.byKey(const ValueKey('refresh_button')), findsNothing);
  });

  testBothViewports('survives a long title and many actions', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkPageScaffold(
        title: 'Photos ' * 20,
        icon: QuarkIcons.photo_library_outlined,
        actions: [
          for (var i = 0; i < 4; i++)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Action $i',
              onPressed: () {},
            ),
        ],
        body: const Text('the grid'),
      ),
      size: size,
      scaffold: false,
    );

    expect(tester.takeException(), isNull);
  });
}
