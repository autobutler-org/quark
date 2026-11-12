import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/image_viewer/current_photo.dart';
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
    bool Function()? failing,
  }) async {
    final requested = <int>[];
    final page = MaterialApp(
      home: ImageViewerPage(
        bytes: bytes,
        name: 'first.jpg',
        initialIndex: 1,
        imageCount: 3,
        onLoadImage: (index) async {
          requested.add(index);
          if (failing?.call() ?? true) throw error;
          return (bytes, 'p$index.jpg', null, null);
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

  // #3486: the failed swipe put the view back on page 1, and a retry that
  // loaded photo 2 left it there, a spinner under a counter reading 3 / 3.
  testWidgets('a retry that loads turns the page to the photo', (tester) async {
    var failing = true;
    await pumpAndSwipe(
      tester,
      Exception('dropped request'),
      failing: () => failing,
    );

    failing = false;
    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byType(CurrentPhoto), findsOneWidget);
  });

  testWidgets('a 404 says the photo is gone and offers no retry', (
    tester,
  ) async {
    final requested = await pumpAndSwipe(tester, const ApiException(404));

    expect(requested, [2]);
    expect(find.textContaining('no longer there'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing);
  });
}
