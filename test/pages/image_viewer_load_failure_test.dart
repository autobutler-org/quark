import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1708: a photo that failed to load always said "Image no longer available"
/// and gave up. Only a 404 means gone; anything else gets a Retry.
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

  /// Pumps the viewer on image 1 of 3 whose loader always throws [error],
  /// swipes to the next photo, and returns how many loads were attempted.
  Future<List<int>> pumpAndSwipe(
    WidgetTester tester,
    Object error, {
    Future<void> Function(NoPreviewException)? saveOriginal,
  }) async {
    final requested = <int>[];
    final page = MaterialApp(
      home: ImageViewerPage(
        saveOriginal: saveOriginal,
        bytes: bytes,
        name: 'first.jpg',
        initialIndex: 1,
        imageCount: 3,
        onLoadImage: (index) async {
          requested.add(index);
          throw error;
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

    await tester.fling(
      find.byType(InteractiveViewer),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();
    return requested;
  }

  testWidgets('a transient failure offers a retry', (tester) async {
    final requested = await pumpAndSwipe(tester, Exception('dropped request'));

    expect(requested, [2]);
    expect(find.text(Errors.message(null, 'load the photo')), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('retry loads the same photo again', (tester) async {
    final requested = await pumpAndSwipe(tester, Exception('dropped request'));

    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pumpAndSettle();

    expect(requested, [2, 2]);
  });

  testWidgets('a 404 says the photo is gone and offers no retry', (
    tester,
  ) async {
    final requested = await pumpAndSwipe(tester, const ApiException(404));

    expect(requested, [2]);
    expect(find.textContaining('no longer there'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing);
  });

  testWidgets('a HEIC without a preview offers the original (#2379)', (
    tester,
  ) async {
    const noPreview = NoPreviewException(
      path: 'trips/IMG_1.heic',
      serial: 'sd1',
      name: 'IMG_1.heic',
    );
    final saved = <String>[];
    await pumpAndSwipe(
      tester,
      noPreview,
      saveOriginal: (e) async => saved.add('${e.serial}:${e.path}'),
    );

    expect(find.text(Errors.noPreview), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Download'));
    await tester.pumpAndSettle();

    expect(saved, ['sd1:trips/IMG_1.heic']);
  });

  testWidgets('a viewer opened on a HEIC without a preview offers the '
      'original (#2379)', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerPage(
          name: 'IMG_1.heic',
          relPath: 'trips/IMG_1.heic',
          loadBytes: () async => throw const NoPreviewException(
            path: 'trips/IMG_1.heic',
            name: 'IMG_1.heic',
          ),
          saveOriginal: (e) async => saved.add(e.path),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(Errors.noPreview), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('image_viewer_download_original')),
    );
    await tester.pumpAndSettle();

    expect(saved, ['trips/IMG_1.heic']);
  });
}
