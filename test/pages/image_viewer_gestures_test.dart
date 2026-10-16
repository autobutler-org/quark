import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/widgets/image_viewer/metadata_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3358: on a phone the viewer ignored a normal thumb swipe, a double-tap
/// toggled the info sheet instead of zooming, and a swipe down did nothing.
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

  /// Pushes the viewer on image 1 of 3 over a host page, at a Pixel 7's
  /// width, and returns the indexes it asks to load.
  Future<List<int>> pushViewer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requested = <int>[];
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('host')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => ImageViewerPage(
          bytes: bytes,
          name: 'first.jpg',
          initialIndex: 1,
          imageCount: 3,
          onLoadImage: (index) async {
            requested.add(index);
            return (bytes, 'next.jpg', null, null);
          },
        ),
      ),
    );
    // Decoding the image takes real async, and it has to be laid out before a
    // gesture can hit it.
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    return requested;
  }

  /// Drags [delta] across the photo a few pixels a frame and lets go with the
  /// finger at rest, so the gesture ends with no fling velocity at all.
  Future<void> dragAndRest(WidgetTester tester, Offset delta) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    final steps = (delta.distance / 20).ceil();
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(delta / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  TransformationController zoomOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!;

  Future<void> doubleTap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  group('swiping', () {
    testWidgets('a short, quick flick turns the page', (tester) async {
      final requested = await pushViewer(tester);
      await tester.fling(find.byType(PageView), const Offset(-80, 0), 1500);
      await tester.pumpAndSettle();
      expect(requested, [2]);
    });

    // A thumb swipe of under half the screen that slows before it lifts has
    // no fling velocity left. It still means "next photo".
    testWidgets('a short swipe that comes to rest turns the page', (
      tester,
    ) async {
      final requested = await pushViewer(tester);
      await dragAndRest(tester, const Offset(-180, 0));
      expect(requested, [2]);
    });

    testWidgets('the same swipe the other way goes back', (tester) async {
      final requested = await pushViewer(tester);
      await dragAndRest(tester, const Offset(180, 0));
      expect(requested, [0]);
    });

    testWidgets('a nudge springs back', (tester) async {
      final requested = await pushViewer(tester);
      await dragAndRest(tester, const Offset(-40, 0));
      expect(requested, isEmpty);
    });
  });

  group('double-tap', () {
    testWidgets('zooms in around the tap and leaves the info sheet alone', (
      tester,
    ) async {
      await pushViewer(tester);
      expect(find.byType(MetadataDrawer), findsOneWidget);

      final photo = tester.getRect(find.byType(InteractiveViewer));
      final at = photo.topLeft + Offset(photo.width / 4, photo.height / 4);
      await doubleTap(tester, at);

      final zoom = zoomOf(tester).value;
      expect(zoom.getMaxScaleOnAxis(), closeTo(2, 0.01));
      // The point under the finger stays put.
      final local = at - photo.topLeft;
      expect(
        MatrixUtils.transformPoint(zoom, local),
        offsetMoreOrLessEquals(local),
      );
      expect(find.byType(MetadataDrawer), findsOneWidget);
    });

    testWidgets('a second double-tap zooms back out', (tester) async {
      await pushViewer(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      await doubleTap(tester, center);
      await doubleTap(tester, center);
      expect(zoomOf(tester).value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    });

    testWidgets('a single tap still closes the info sheet', (tester) async {
      await pushViewer(tester);
      await tester.tap(find.byType(InteractiveViewer));
      // A tap waits out the double-tap window before it counts as one.
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.byType(MetadataDrawer), findsNothing);
      expect(zoomOf(tester).value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    });
  });

  group('swiping down', () {
    testWidgets('a flick down closes the viewer', (tester) async {
      await pushViewer(tester);
      await tester.fling(find.byType(PageView), const Offset(0, 150), 1500);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('a long slow drag down closes the viewer', (tester) async {
      await pushViewer(tester);
      await dragAndRest(tester, const Offset(0, 250));
      expect(find.byType(ImageViewerPage), findsNothing);
    });

    testWidgets('a short drag down springs back', (tester) async {
      await pushViewer(tester);
      await dragAndRest(tester, const Offset(0, 40));
      expect(find.byType(ImageViewerPage), findsOneWidget);
    });

    // A pinch whose lower finger does all the moving travels down far enough
    // to look like a swipe before it looks like a pinch. It must zoom.
    testWidgets('a pinch with one finger still zooms instead', (tester) async {
      await pushViewer(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final still = await tester.startGesture(center - const Offset(0, 30));
      final moving = await tester.startGesture(center + const Offset(0, 30));
      for (var i = 0; i < 12; i++) {
        await moving.moveBy(const Offset(0, 15));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await still.up();
      await moving.up();
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsOneWidget);
      expect(zoomOf(tester).value.getMaxScaleOnAxis(), greaterThan(1.01));
    });

    testWidgets('a swipe up does not close it', (tester) async {
      await pushViewer(tester);
      await tester.fling(find.byType(PageView), const Offset(0, -150), 1500);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsOneWidget);
    });
  });

  // #1707: zoomed in, a drag in any direction moves around the photo. It
  // must neither turn the page nor close the viewer.
  group('zoomed in', () {
    Future<void> zoomIn(WidgetTester tester) async {
      await doubleTap(tester, tester.getCenter(find.byType(InteractiveViewer)));
      expect(
        zoomOf(tester).value.getMaxScaleOnAxis(),
        greaterThanOrEqualTo(1.01),
      );
    }

    testWidgets('a horizontal drag pans instead of turning the page', (
      tester,
    ) async {
      final requested = await pushViewer(tester);
      await zoomIn(tester);
      final before = zoomOf(tester).value.getTranslation().x;
      await dragAndRest(tester, const Offset(-120, 0));
      expect(requested, isEmpty);
      expect(zoomOf(tester).value.getTranslation().x, lessThan(before));
    });

    testWidgets('a drag down pans instead of closing', (tester) async {
      await pushViewer(tester);
      await zoomIn(tester);
      final before = zoomOf(tester).value.getTranslation().y;
      await dragAndRest(tester, const Offset(0, 120));
      expect(find.byType(ImageViewerPage), findsOneWidget);
      expect(zoomOf(tester).value.getTranslation().y, greaterThan(before));
    });
  });
}
