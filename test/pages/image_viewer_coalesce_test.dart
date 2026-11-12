import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1710: a swipe that arrived while a download was still in flight used to be
/// thrown away, and the page then snapped back to the photo the viewer already
/// had. Navigations coalesce instead — the newest target wins and the earlier
/// ones drop their results.
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

  /// Pumps the viewer on photo 1 of 5, with every load parked on a completer
  /// the test finishes by hand so downloads can be left in flight.
  Future<Map<int, Completer<void>>> pumpViewer(WidgetTester tester) async {
    final gates = <int, Completer<void>>{};
    final page = MaterialApp(
      home: ImageViewerPage(
        bytes: bytes,
        name: 'photo-0.jpg',
        initialIndex: 0,
        imageCount: 5,
        onLoadImage: (index) async {
          await (gates[index] ??= Completer<void>()).future;
          return (bytes, 'photo-$index.jpg', null, null);
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
    return gates;
  }

  /// Pumps a second of frames. [WidgetTester.pumpAndSettle] cannot be used
  /// once a load is in flight: the pages the finger dragged in show a spinner,
  /// and its animation never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> swipeLeft(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await settle(tester);
  }

  testWidgets('a swipe during a download lands on the newest photo', (
    tester,
  ) async {
    final gates = await pumpViewer(tester);

    // Three swipes in a row, none of the downloads answered yet.
    await swipeLeft(tester);
    await swipeLeft(tester);
    await swipeLeft(tester);
    expect(gates.keys.toList()..sort(), [1, 2, 3]);

    // The superseded downloads answer first and must change nothing.
    gates[1]!.complete();
    gates[2]!.complete();
    await settle(tester);
    expect(find.text('1 / 5'), findsOneWidget);

    gates[3]!.complete();
    await settle(tester);
    expect(find.text('4 / 5'), findsOneWidget);
  });

  // The recovery that puts the view back after a failed load must not fire
  // while a newer navigation is still running, or it drags the user backwards.
  testWidgets('the newest photo is not snapped back to an older one', (
    tester,
  ) async {
    final gates = await pumpViewer(tester);
    await swipeLeft(tester);
    await swipeLeft(tester);

    gates[2]!.complete();
    await settle(tester);
    gates[1]!.complete();
    await settle(tester);

    expect(find.text('3 / 5'), findsOneWidget);
  });

  // The chevrons drive the same coalescing: they stay enabled while a download
  // is in flight, and each press steps on from the last one asked for.
  testWidgets('repeated next presses step past the in-flight photo', (
    tester,
  ) async {
    final gates = await pumpViewer(tester);
    final next = find.byTooltip('Next (→)');

    await tester.tap(next);
    await settle(tester);
    await tester.tap(next);
    await settle(tester);

    expect(gates.keys.toList()..sort(), [1, 2]);

    gates[1]!.complete();
    gates[2]!.complete();
    await settle(tester);
    expect(find.text('3 / 5'), findsOneWidget);
  });
}
