import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1707: on iOS the route's left-edge back-swipe competed with the photo
/// page view and won near the bezel, so a swipe that started too far left
/// left the viewer instead of turning the page. The viewer refuses that pop
/// and closes itself by hand instead.
void main() {
  // 64x64 solid PNG — the viewer needs bytes it can actually decode.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pushes the viewer on top of a host page and hands back the route it was
  /// pushed on, so a test can read the disposition the navigator sees.
  Future<(MaterialPageRoute<bool>, Future<bool?>)> pushViewer(
    WidgetTester tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('host')),
      ),
    );

    final route = MaterialPageRoute<bool>(
      builder: (_) => ImageViewerPage(
        bytes: bytes,
        name: 'first.jpg',
        // No relPath: metadata would otherwise go out to the network.
        initialIndex: 1,
        imageCount: 3,
        onLoadImage: (index) async => (bytes, 'next.jpg', null, null),
      ),
    );
    final result = navigatorKey.currentState!.push(route);

    // Decoding the image takes real async before the page is laid out.
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    return (route, result);
  }

  /// The system back button and the iOS edge swipe both arrive here.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
  }

  // The one assertion that pins the fix: `popGestureEnabled` is what
  // CupertinoRouteTransitionMixin asks before it arms the edge gesture, and
  // a doNotPop disposition is what turns it off.
  testWidgets('the viewer route refuses the edge back-swipe', (tester) async {
    final (route, _) = await pushViewer(tester);
    expect(route.popDisposition, RoutePopDisposition.doNotPop);
    expect(route.popGestureEnabled, isFalse);
  });

  testWidgets('a system back still closes the viewer with its result', (
    tester,
  ) async {
    final (_, result) = await pushViewer(tester);
    expect(find.byType(ImageViewerPage), findsOneWidget);

    await systemBack(tester);
    await tester.pumpAndSettle();

    expect(find.byType(ImageViewerPage), findsNothing);
    // The caller gets the list-changed flag, not the null a plain pop sends.
    expect(await result, isFalse);
  });

  testWidgets('the app bar close button still returns the result', (
    tester,
  ) async {
    final (_, result) = await pushViewer(tester);
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();

    expect(find.byType(ImageViewerPage), findsNothing);
    expect(await result, isFalse);
  });

  testWidgets('escape still returns the result', (tester) async {
    final (_, result) = await pushViewer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(ImageViewerPage), findsNothing);
    expect(await result, isFalse);
  });
}
