// The one-row scroller behind every toolbar (#2770).
//
// The content is 900 pixels wide: more than the narrow viewport shows, less
// than the wide one, so the same widget is asserted both overflowing and not.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _left = ValueKey('toolbar_scroll_left');
const _right = ValueKey('toolbar_scroll_right');

/// Six 150 pixel boxes, keyed `item_0` to `item_5`.
final List<Widget> _items = [
  for (var i = 0; i < 6; i++)
    SizedBox(key: ValueKey('item_$i'), width: 150, height: 40),
];

final Widget _content = Row(children: _items);

/// How far the 900 pixel content can scroll in the 360 pixel viewport.
const double _maxScroll = 900 - 360;

double _pixels(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

/// Connects a mouse, which is what brings the chevrons out.
Future<void> _connectMouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(1, 1));
  addTearDown(mouse.removePointer);
  await tester.pump();
}

Future<void> _wheel(WidgetTester tester, Offset delta) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse)
    ..hover(const Offset(100, 20));
  await tester.sendEventToBinding(pointer.scroll(delta));
  await tester.pump();
}

void main() {
  testBothViewports('shows its child with no chevrons and no mouse', (
    tester,
    size,
  ) async {
    await pumpAt(tester, QuarkToolbarScroller(child: _content), size: size);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('item_0')), findsOneWidget);
    expect(find.byKey(_left), findsNothing);
    expect(find.byKey(_right), findsNothing);
  });

  testBothViewports('a mouse brings out a chevron only where there is more', (
    tester,
    size,
  ) async {
    await pumpAt(tester, QuarkToolbarScroller(child: _content), size: size);
    await _connectMouse(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(_left), findsNothing);
    expect(
      find.byKey(_right),
      size == narrowViewport ? findsOneWidget : findsNothing,
    );
  });

  testWidgets('a child that wraps is held to one row', (tester) async {
    await pumpAt(
      tester,
      QuarkToolbarScroller(child: Wrap(children: _items)),
      size: narrowViewport,
    );

    expect(tester.getSize(find.byType(QuarkToolbarScroller)).height, 40);
  });

  testWidgets('the chevrons scroll to the far end and back', (tester) async {
    await pumpAt(
      tester,
      QuarkToolbarScroller(child: _content),
      size: narrowViewport,
    );
    await _connectMouse(tester);

    await tester.tap(find.byKey(_right));
    await tester.pump();
    expect(_pixels(tester), lessThan(288), reason: 'the scroll is animated');
    await tester.pumpAndSettle();
    expect(_pixels(tester), 360 * QuarkToolbarScroller.scrollFraction);
    expect(find.byKey(_left), findsOneWidget);
    expect(find.byKey(_right), findsOneWidget);
    expect(find.byTooltip('Scroll left'), findsOneWidget);
    expect(find.byTooltip('Scroll right'), findsOneWidget);

    await tester.tap(find.byKey(_right));
    await tester.pumpAndSettle();
    expect(_pixels(tester), _maxScroll);
    expect(find.byKey(_right), findsNothing);

    await tester.tap(find.byKey(_left));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_left));
    await tester.pumpAndSettle();
    expect(_pixels(tester), 0);
    expect(find.byKey(_left), findsNothing);
  });

  testWidgets('a chevron jumps when animations are disabled', (tester) async {
    await pumpAt(
      tester,
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: QuarkToolbarScroller(child: _content),
      ),
      size: narrowViewport,
    );
    await _connectMouse(tester);

    await tester.tap(find.byKey(_right));
    await tester.pump();

    expect(_pixels(tester), 360 * QuarkToolbarScroller.scrollFraction);
  });

  testWidgets('a chevron jumps under platform reduce motion', (tester) async {
    await pumpAt(
      tester,
      QuarkToolbarScroller(child: _content),
      size: narrowViewport,
    );
    await _connectMouse(tester);
    // Turned on after the first build: it is read at each press.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.tap(find.byKey(_right));
    await tester.pump();

    expect(_pixels(tester), 360 * QuarkToolbarScroller.scrollFraction);
  });

  testWidgets('a drag scrolls it', (tester) async {
    await pumpAt(
      tester,
      QuarkToolbarScroller(child: _content),
      size: narrowViewport,
    );

    await tester.drag(find.byType(QuarkToolbarScroller), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(_pixels(tester), greaterThan(0));
  });

  testWidgets('a vertical wheel scrolls it sideways, then lets go', (
    tester,
  ) async {
    await pumpAt(
      tester,
      ListView(
        children: [
          QuarkToolbarScroller(child: _content),
          const SizedBox(height: 2000),
        ],
      ),
      size: narrowViewport,
    );
    double pagePixels() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    double toolbarPixels() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(QuarkToolbarScroller),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;

    await _wheel(tester, const Offset(0, 100));
    expect(toolbarPixels(), 100);
    expect(pagePixels(), 0, reason: 'the toolbar took the wheel');

    await _wheel(tester, const Offset(0, 1000));
    expect(toolbarPixels(), _maxScroll);

    // Short of the toolbar's own height, so it is still on screen to read.
    await _wheel(tester, const Offset(0, 30));
    expect(toolbarPixels(), _maxScroll);
    expect(pagePixels(), 30, reason: 'at its end, the page scrolls again');
  });

  testWidgets('right to left, the far end is on the left', (tester) async {
    await pumpAt(
      tester,
      Directionality(
        textDirection: TextDirection.rtl,
        child: QuarkToolbarScroller(child: _content),
      ),
      size: narrowViewport,
    );
    await _connectMouse(tester);

    expect(find.byKey(_right), findsNothing);
    await tester.tap(find.byKey(_left));
    await tester.pumpAndSettle();

    expect(_pixels(tester), 360 * QuarkToolbarScroller.scrollFraction);
    expect(find.byKey(_right), findsOneWidget);
  });

  testWidgets('the edges follow a resize', (tester) async {
    await pumpAt(
      tester,
      QuarkToolbarScroller(child: _content),
      size: narrowViewport,
    );
    await _connectMouse(tester);
    expect(find.byKey(_right), findsOneWidget);

    tester.view.physicalSize = wideViewport;
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(_right), findsNothing);
  });
}
