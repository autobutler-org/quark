import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/router.dart';

/// #2607: on a phone, picking a sidebar row brings the grid back into view.
/// Under reduced motion it jumps there instead of scrolling.
void main() {
  // The test platform is Android, so the page also asks photo_manager for the
  // device library; denying it lets the page settle.
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          photoManager,
          (_) async => throw MissingPluginException(),
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManager, null);
  });

  /// Pumps the page at a phone size short enough to scroll, scrolled to the
  /// top so the sidebar shows, and returns its scroll position.
  Future<ScrollPosition> pumpAtSidebar(WidgetTester tester) async {
    // Short enough that the sidebar and the grid scroll as one.
    tester.view.physicalSize = const Size(390, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: AppRoutes.photos,
      routes: [
        GoRoute(
          path: AppRoutes.photos,
          builder: (context, state) => const PhotosPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(PhotosPage),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(0);
    await tester.pump();
    return position;
  }

  Future<void> pickAllPhotos(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('album_sidebar_all_photos')));
    await tester.pump();
  }

  testWidgets('a sidebar pick scrolls to the grid', (tester) async {
    final position = await pumpAtSidebar(tester);

    await pickAllPhotos(tester);
    expect(position.pixels, 0, reason: 'the scroll is still on its way');

    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('a sidebar pick jumps to the grid under reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final position = await pumpAtSidebar(tester);

    await pickAllPhotos(tester);
    expect(
      position.pixels,
      greaterThan(0),
      reason: 'already there on the first frame',
    );
  });
}
