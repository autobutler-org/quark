import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3357: in a 364-photo library the viewer's counter read "41 / 50", because
/// the total it showed was the size of the page of the list loaded so far, and
/// the viewer stopped at photo 50 because it had no way to ask for more.
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

  /// Holds the next page back while set.
  Completer<void>? gate;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gate = null;
  });

  /// A list that holds [loaded] of [total] photos and grows a page of 50 at a
  /// time when asked.
  late int loaded;
  late int loadMoreCalls;
  late List<int> requested;

  Future<void> pumpViewer(
    WidgetTester tester, {
    required int initialIndex,
    int? totalCount = 364,
  }) async {
    loaded = 50;
    loadMoreCalls = 0;
    requested = [];
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImageViewerPage(
            bytes: bytes,
            name: 'p$initialIndex.jpg',
            initialIndex: initialIndex,
            imageCount: loaded,
            totalCount: totalCount,
            getImageCount: () async => loaded,
            onLoadMore: () async {
              loadMoreCalls++;
              await gate?.future;
              loaded = (loaded + 50).clamp(0, 364);
            },
            onLoadImage: (index) async {
              requested.add(index);
              if (index >= loaded) return (null, '', null, null);
              return (bytes, 'p$index.jpg', null, null);
            },
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the counter counts the whole library, not the loaded page', (
    tester,
  ) async {
    await pumpViewer(tester, initialIndex: 40);
    expect(find.text('41 / 364'), findsOneWidget);
    expect(find.textContaining('/ 50'), findsNothing);
  });

  testWidgets('without a library total it counts what it was given', (
    tester,
  ) async {
    await pumpViewer(tester, initialIndex: 40, totalCount: null);
    expect(find.text('41 / 50'), findsOneWidget);
  });

  testWidgets('stepping past the loaded page fetches the next one', (
    tester,
  ) async {
    await pumpViewer(tester, initialIndex: 48);
    await next(tester);
    expect(find.text('50 / 364'), findsOneWidget);
    // Within reach of the end of what is loaded, the next page is fetched
    // ahead of the user getting there.
    expect(loadMoreCalls, 1);

    await next(tester);
    expect(requested, [49, 50]);
    expect(find.text('51 / 364'), findsOneWidget);
    expect(find.byTooltip('Next (→)'), findsOneWidget);
  });

  testWidgets('a step past the loaded page waits for it to load', (
    tester,
  ) async {
    // On the last loaded photo, the step outruns the page fetched ahead of
    // it: it has to wait for that page rather than fail.
    gate = Completer<void>();
    await pumpViewer(tester, initialIndex: 49);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    // The page it lands on spins until the photo is in, so it never settles.
    await tester.pump(const Duration(milliseconds: 500));
    expect(requested, isEmpty);
    expect(find.text('50 / 364'), findsOneWidget);

    gate!.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(requested, [50]);
    expect(find.text('51 / 364'), findsOneWidget);
    expect(loadMoreCalls, 1);
  });
}
