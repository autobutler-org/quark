import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/widgets/image_viewer/current_photo.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2607: the viewer slides to the next photo and turns a rotated one, and
/// under reduced motion it does neither: the page and the rotation land on
/// the first frame.
void main() {
  // 64x64 solid PNG — the photo needs a real box to lay out.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// Pumps the viewer wide, on photo 1 of 3. A [relPath] makes it a Quark
  /// photo, which is what offers rotation.
  Future<void> pumpViewer(WidgetTester tester, {String? relPath}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerPage(
          bytes: bytes,
          name: 'first.jpg',
          relPath: relPath,
          initialIndex: 1,
          imageCount: 3,
          onLoadImage: (index) async => (bytes, 'photo$index.jpg', null, null),
        ),
      ),
    );
    await tester.pump();
  }

  double page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!;

  Animation<double> rotation(WidgetTester tester) =>
      tester.widget<CurrentPhoto>(find.byType(CurrentPhoto)).rotation;

  testWidgets('the next chevron slides to the next photo', (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.byTooltip('Next (→)'));
    await tester.pump();
    expect(page(tester), 1, reason: 'the slide has only begun');

    await tester.pumpAndSettle();
    expect(page(tester), 2);
  });

  testWidgets('the next chevron jumps under reduced motion', (tester) async {
    reduceMotion(tester);
    await pumpViewer(tester);

    await tester.tap(find.byTooltip('Next (→)'));
    await tester.pump();
    expect(page(tester), 2);
  });

  testWidgets('the arrow key jumps under reduced motion', (tester) async {
    reduceMotion(tester);
    await pumpViewer(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(page(tester), 0);
  });

  testWidgets('rotating turns the photo', (tester) async {
    await pumpViewer(tester, relPath: 'Photos/first.jpg');

    await tester.tap(find.byIcon(QuarkIcons.rotate_90_degrees_cw_outlined));
    await tester.pump();
    expect(rotation(tester).isAnimating, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('rotating lands at once under reduced motion', (tester) async {
    reduceMotion(tester);
    await pumpViewer(tester, relPath: 'Photos/first.jpg');

    await tester.tap(find.byIcon(QuarkIcons.rotate_90_degrees_cw_outlined));
    await tester.pump();
    expect(rotation(tester).isCompleted, isTrue);
    await tester.pumpAndSettle();
  });
}
