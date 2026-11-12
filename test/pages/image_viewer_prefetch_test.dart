import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1710: every navigation was a cold, full-resolution download. The viewer's
/// half of the fix is warming its neighbors and decoding at display size.
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

  /// Pumps the viewer on image 2 of 5, recording loads and prefetches.
  Future<void> pumpViewer(
    WidgetTester tester, {
    required List<int> loaded,
    required List<int> prefetched,
    Object? prefetchError,
  }) async {
    final page = MaterialApp(
      home: ImageViewerPage(
        bytes: bytes,
        name: 'second.jpg',
        initialIndex: 2,
        imageCount: 5,
        onLoadImage: (index) async {
          loaded.add(index);
          return (bytes, 'other.jpg', null, null);
        },
        onPrefetchImage: (index) async {
          prefetched.add(index);
          if (prefetchError != null) throw prefetchError;
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
  }

  testWidgets('opening the viewer warms the neighboring photos', (
    tester,
  ) async {
    final loaded = <int>[];
    final prefetched = <int>[];
    await pumpViewer(tester, loaded: loaded, prefetched: prefetched);

    expect(prefetched..sort(), [1, 3]);
    // The photo on screen was handed in; prefetch must not re-download it.
    expect(loaded, isEmpty);
  });

  testWidgets('navigating warms the next photo along', (tester) async {
    final loaded = <int>[];
    final prefetched = <int>[];
    await pumpViewer(tester, loaded: loaded, prefetched: prefetched);
    prefetched.clear();

    await tester.fling(
      find.byType(InteractiveViewer),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(loaded, [3]);
    expect(prefetched..sort(), [2, 4]);
  });

  // A photo the user never asked for failing is not their problem, and a grid
  // refresh or a snackbar over it would be a regression of #1708's copy.
  testWidgets('a prefetch failure is silent', (tester) async {
    final loaded = <int>[];
    final prefetched = <int>[];
    await pumpViewer(
      tester,
      loaded: loaded,
      prefetched: prefetched,
      prefetchError: Exception('quark went away'),
    );

    expect(prefetched, isNotEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the photo decodes at display size, not sensor size', (
    tester,
  ) async {
    await pumpViewer(tester, loaded: [], prefetched: []);

    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.width, isNull, reason: 'layout size is unchanged');
    // Sized off the photo area in physical pixels: enough to fill it however
    // the photo is oriented, never more than the window could show.
    final decodeWidth = (image.image as ResizeImage).width;
    expect(decodeWidth, isNotNull);
    expect(decodeWidth, greaterThan(tester.view.physicalSize.shortestSide / 2));
    expect(
      decodeWidth,
      lessThanOrEqualTo(tester.view.physicalSize.longestSide),
    );
  });

  // A downscaled decode left in place under magnification is worse than a slow
  // one — the whole point of pinching is to see the detail.
  testWidgets('zooming in swaps to the full-resolution decode', (tester) async {
    await pumpViewer(tester, loaded: [], prefetched: []);
    expect(
      tester.widget<Image>(find.byType(Image).first).image,
      isA<ResizeImage>(),
    );

    final center = tester.getCenter(find.byType(InteractiveViewer));
    final left = await tester.startGesture(center - const Offset(20, 0));
    final right = await tester.startGesture(center + const Offset(20, 0));
    await left.moveBy(const Offset(-120, 0));
    await right.moveBy(const Offset(120, 0));
    await tester.pump();

    expect(
      tester.widget<Image>(find.byType(Image).first).image,
      isA<MemoryImage>(),
    );

    await left.up();
    await right.up();
    await tester.pumpAndSettle();
  });
}
