// The sidebar-plus-content layout, and the one breakpoint the app collapses
// at.
//
// The narrow cases are the point of the file: the photos view rendered
// nothing at all below 900px because its collapsed sidebar ended in an
// `Expanded` inside a sliver (#1599), so every case here checks that the
// sidebar and the content are both actually on screen, not merely that
// nothing threw.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A sidebar tall enough to need scrolling, and a content list long enough
/// that the collapsed layout has something to scroll past.
Widget buildSplitView({
  bool isSidebarOpen = true,
  VoidCallback? onToggleSidebar,
  ScrollController? controller,
  Key? collapsedSidebarKey,
}) {
  return QuarkSplitView(
    isSidebarOpen: isSidebarOpen,
    onToggleSidebar: onToggleSidebar,
    controller: controller,
    collapsedSidebarKey: collapsedSidebarKey,
    sidebar: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [Text('Albums'), SizedBox(height: 200)],
    ),
    slivers: [
      SliverList.builder(
        itemCount: 30,
        itemBuilder: (context, index) =>
            SizedBox(height: 48, child: Text('row $index')),
      ),
    ],
  );
}

void main() {
  testWidgets('wide lays the sidebar out as a pane beside the content', (
    tester,
  ) async {
    await pumpAt(tester, buildSplitView(), size: wideViewport);

    expect(tester.takeException(), isNull);
    expect(find.text('Albums'), findsOneWidget);
    final pane = tester.getRect(
      find.byKey(const ValueKey('split_view_sidebar')),
    );
    expect(pane.width, QuarkSplitView.defaultSidebarWidth);
    expect(pane.left, 0);
    // The content starts after the pane and its divider, not under it.
    expect(
      tester.getRect(find.text('row 0')).left,
      greaterThanOrEqualTo(pane.right),
    );
  });

  testWidgets('narrow stacks the sidebar above the content, full width', (
    tester,
  ) async {
    await pumpAt(tester, buildSplitView(), size: narrowViewport);

    expect(tester.takeException(), isNull);
    expect(find.text('Albums'), findsOneWidget);
    final sidebar = tester.getRect(
      find.byKey(const ValueKey('split_view_sidebar')),
    );
    expect(sidebar.width, narrowViewport.width);
    expect(
      tester.getRect(find.text('row 0')).top,
      greaterThanOrEqualTo(sidebar.bottom),
    );
  });

  testWidgets('narrow scrolls the sidebar away with the content', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpAt(
      tester,
      buildSplitView(controller: controller),
      size: narrowViewport,
    );

    // One scroll view, so the sidebar is above the content rather than
    // stealing height from it.
    expect(find.byType(CustomScrollView), findsOneWidget);
    controller.jumpTo(300);
    await tester.pump();

    expect(find.text('Albums'), findsNothing);
    expect(find.text('row 5'), findsOneWidget);
  });

  testWidgets('narrow hides the sidebar when the caller closes it', (
    tester,
  ) async {
    await pumpAt(
      tester,
      buildSplitView(isSidebarOpen: false),
      size: narrowViewport,
    );

    expect(find.text('Albums'), findsNothing);
    expect(find.byKey(const ValueKey('split_view_sidebar')), findsNothing);
    expect(find.text('row 0'), findsOneWidget);
  });

  testWidgets('wide keeps the sidebar even when the caller closes it', (
    tester,
  ) async {
    await pumpAt(
      tester,
      buildSplitView(isSidebarOpen: false),
      size: wideViewport,
    );

    // isSidebarOpen is about the collapsed layout; the pane is not optional.
    expect(find.text('Albums'), findsOneWidget);
  });

  testWidgets('reports a toggle rather than holding the state itself', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      buildSplitView(onToggleSidebar: () => events.add('toggle')),
      size: narrowViewport,
    );

    await tester.tap(find.byKey(const ValueKey('split_view_toggle')));
    await tester.pump();

    expect(events, ['toggle']);
    // Nothing moved: the caller owns isSidebarOpen.
    expect(find.text('Albums'), findsOneWidget);
  });

  testWidgets('offers no toggle when the caller supplies no callback', (
    tester,
  ) async {
    await pumpAt(tester, buildSplitView(), size: narrowViewport);

    expect(find.byKey(const ValueKey('split_view_toggle')), findsNothing);
  });

  testWidgets('offers no toggle in the wide layout', (tester) async {
    await pumpAt(
      tester,
      buildSplitView(onToggleSidebar: () {}),
      size: wideViewport,
    );

    expect(find.byKey(const ValueKey('split_view_toggle')), findsNothing);
  });

  testWidgets('the toggle names itself', (tester) async {
    await pumpAt(
      tester,
      buildSplitView(onToggleSidebar: () {}),
      size: narrowViewport,
    );

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
    }
  });

  testWidgets('hands the collapsed sidebar a key the caller can measure', (
    tester,
  ) async {
    final navKey = GlobalKey();
    await pumpAt(
      tester,
      buildSplitView(collapsedSidebarKey: navKey),
      size: narrowViewport,
    );

    final box = navKey.currentContext!.findRenderObject() as RenderBox?;
    expect(
      box,
      isNotNull,
      reason: 'the key has to land on a box, not a sliver',
    );
    expect(box!.hasSize, isTrue);
    expect(box.size.height, greaterThan(0));
  });

  testWidgets('crossing the breakpoint keeps laying out, both ways', (
    tester,
  ) async {
    await pumpAt(tester, buildSplitView(), size: wideViewport);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = narrowViewport;
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'wide to narrow');
    expect(find.text('Albums'), findsOneWidget);

    tester.view.physicalSize = wideViewport;
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'narrow to wide');
    expect(find.text('Albums'), findsOneWidget);
  });

  testWidgets('honors a sidebar width of the caller\'s choosing', (
    tester,
  ) async {
    await pumpAt(
      tester,
      QuarkSplitView(
        sidebarWidth: 360,
        physics: const AlwaysScrollableScrollPhysics(),
        sidebar: const Text('Albums'),
        slivers: [
          SliverList.builder(
            itemCount: 3,
            itemBuilder: (context, index) => Text('row $index'),
          ),
        ],
      ),
      size: wideViewport,
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('split_view_sidebar'))).width,
      360,
    );
    expect(
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).physics,
      isA<AlwaysScrollableScrollPhysics>(),
      reason: 'the physics the caller passed have to reach the scroll view',
    );
  });

  testWidgets('isCollapsed answers for the window it is asked about', (
    tester,
  ) async {
    late bool narrow;
    late double narrowContent;
    await pumpAt(
      tester,
      Builder(
        builder: (context) {
          narrow = QuarkSplitView.isCollapsed(context);
          narrowContent = QuarkSplitView.contentWidthOf(context);
          return const SizedBox();
        },
      ),
      size: narrowViewport,
    );
    expect(narrow, isTrue);
    expect(
      narrowContent,
      narrowViewport.width,
      reason: 'the collapsed content pane is the whole window',
    );

    late bool wide;
    late double wideContent;
    await pumpAt(
      tester,
      Builder(
        builder: (context) {
          wide = QuarkSplitView.isCollapsed(context);
          wideContent = QuarkSplitView.contentWidthOf(context);
          return const SizedBox();
        },
      ),
      size: wideViewport,
    );
    expect(wide, isFalse);
    expect(
      wideContent,
      wideViewport.width -
          QuarkSplitView.defaultSidebarWidth -
          QuarkSplitView.dividerWidth,
      reason: 'the pane and its divider come off the content width',
    );
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the divider color comes from the tokens', (
      tester,
    ) async {
      await pumpAt(
        tester,
        buildSplitView(),
        size: wideViewport,
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final divider = tester.widget<VerticalDivider>(
        find.byType(VerticalDivider),
      );
      expect(divider.color, tokens.border);
    });
  }

  testBothViewports('survives a tall sidebar and a long content list', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkSplitView(
        sidebar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (var i = 0; i < 40; i++) Text('album $i')],
        ),
        slivers: [
          SliverList.builder(
            itemCount: 500,
            itemBuilder: (context, index) => SizedBox(
              height: 48,
              child: Text('a very long row label $index' * 3),
            ),
          ),
        ],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });
}
