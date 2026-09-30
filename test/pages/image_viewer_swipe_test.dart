import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1707: swiping the photo left/right did nothing, and a swipe that did
/// register gave no feedback while the finger moved. A [PageView] carries the
/// photo so it tracks the finger and settles with an animation.
void main() {
  // 64x64 solid PNG — the photo needs a real box for a gesture to land on.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps the viewer on image 1 of 3 and returns the indexes it asks to load.
  Future<List<int>> pumpViewer(WidgetTester tester) async {
    final requested = <int>[];
    final page = MaterialApp(
      home: ImageViewerPage(
        bytes: bytes,
        name: 'first.jpg',
        initialIndex: 1,
        imageCount: 3,
        onLoadImage: (index) async {
          requested.add(index);
          return (bytes, 'next.jpg', null, null);
        },
      ),
    );
    // Decoding the image takes real async, and it has to be laid out before a
    // gesture can hit it.
    await tester.runAsync(() async {
      await tester.pumpWidget(page);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    return requested;
  }

  /// Drags [dx] across the photo the way a finger does: 25 logical pixels per
  /// frame. A single big jump is not the same gesture — it clears
  /// InteractiveViewer's 36px pan slop in the same event that it clears the
  /// page scroll slop, and the scale recognizer takes the tie.
  Future<TestGesture> dragBy(WidgetTester tester, double dx) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    final steps = (dx.abs() / 25).ceil();
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  testWidgets('swiping left loads the next image', (tester) async {
    final requested = await pumpViewer(tester);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(requested, [2]);
  });

  testWidgets('swiping right loads the previous image', (tester) async {
    final requested = await pumpViewer(tester);
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(requested, [0]);
  });

  // The point of the PageView: the photo moves with the finger instead of
  // waiting for it to lift, so the swipe is visible while it happens (#1707).
  testWidgets('the photo follows the finger mid-swipe', (tester) async {
    await pumpViewer(tester);
    final startX = tester.getCenter(find.byType(Image)).dx;

    final gesture = await dragBy(tester, -200);
    expect(tester.getCenter(find.byType(Image)).dx, lessThan(startX - 100));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  // No flick needed: dragging most of the way across settles on the next page
  // on its own, which the old velocity threshold could not do.
  testWidgets('a slow drag past half the page navigates', (tester) async {
    final requested = await pumpViewer(tester);
    final width = tester.getSize(find.byType(PageView)).width;
    final gesture = await dragBy(tester, -width * 0.6);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requested, [2]);
  });

  // A drag that gives up before halfway springs back instead of navigating.
  testWidgets('a short drag springs back', (tester) async {
    final requested = await pumpViewer(tester);
    final gesture = await dragBy(tester, -60);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requested, isEmpty);
  });

  // The mobile body stacks the photo under a drawer instead of putting it in
  // a Row, so the PageView gets its constraints a different way there.
  testWidgets('swiping works on a phone-width layout', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requested = await pumpViewer(tester);
    await tester.fling(find.byType(PageView), const Offset(-200, 0), 1200);
    await tester.pumpAndSettle();
    expect(requested, [2]);
  });

  testWidgets('a tap does not navigate', (tester) async {
    final requested = await pumpViewer(tester);
    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();
    expect(requested, isEmpty);
  });

  // The chevrons and the arrow keys drive the same PageView, so they animate
  // the same way a swipe does.
  testWidgets('the app bar chevron navigates', (tester) async {
    final requested = await pumpViewer(tester);
    await tester.tap(find.byTooltip('Next (\u2192)'));
    await tester.pumpAndSettle();
    expect(requested, [2]);
  });

  // Under reduced motion the chevron jumps straight to the next photo instead
  // of sliding across (#2607), so the page changes on the very next frame.
  testWidgets('the chevron jumps under reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final requested = await pumpViewer(tester);

    await tester.tap(find.byTooltip('Next (\u2192)'));
    await tester.pump();
    expect(requested, [2]);
    await tester.pumpAndSettle();
  });

  // Without it, the same tap is still mid-slide one frame later.
  testWidgets('the chevron slides without reduced motion', (tester) async {
    final requested = await pumpViewer(tester);

    await tester.tap(find.byTooltip('Next (\u2192)'));
    await tester.pump();
    expect(requested, isEmpty);
    await tester.pumpAndSettle();
    expect(requested, [2]);
  });

  // A zoomed photo pans inside the InteractiveViewer, so the page must stop
  // scrolling until the pinch is undone.
  testWidgets('pinching to zoom locks page scrolling', (tester) async {
    await pumpViewer(tester);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<PageScrollPhysics>(),
    );

    final center = tester.getCenter(find.byType(PageView));
    final left = await tester.startGesture(center - const Offset(20, 0));
    final right = await tester.startGesture(center + const Offset(20, 0));
    for (var i = 0; i < 10; i++) {
      await left.moveBy(const Offset(-8, 0));
      await right.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    await left.up();
    await right.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the arrow keys navigate', (tester) async {
    final requested = await pumpViewer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(requested, [0]);
  });

  // A pinch is given no snap-back, so one that ends near 1x settles wherever
  // the fingers left it rather than on exactly 1.0. A residual that small is
  // not magnification, and treating it as such would pin the physics and kill
  // the swipe for as long as the photo stayed on screen (#1707).
  testWidgets('a residual near-1x scale leaves the page scrollable', (
    tester,
  ) async {
    await pumpViewer(tester);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;

    controller.value = Matrix4.diagonal3Values(1.000001, 1.000001, 1);
    await tester.pump();
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<PageScrollPhysics>(),
    );

    controller.value = Matrix4.diagonal3Values(1.5, 1.5, 1);
    await tester.pump();
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
  });
}
