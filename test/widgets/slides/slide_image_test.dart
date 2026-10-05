import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/slide_image.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// An image provider whose picture arrives when [frame] completes.
class FakeImage extends ImageProvider<FakeImage> {
  FakeImage(this.frame);

  final Future<ImageInfo> frame;

  @override
  Future<FakeImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(FakeImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(frame);
}

/// A picture on a slide shows a placeholder until it loads, the picture once
/// it does, and a broken-picture box when it never will (#1153).
void main() {
  Future<void> pumpImage(WidgetTester tester, ImageProvider image) =>
      tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 180,
                child: SlideImage(image: image, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      );

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('loading, then the picture ($name)', (tester) async {
      tap.setViewport(tester, size);
      final frame = Completer<ImageInfo>();
      await pumpImage(tester, FakeImage(frame.future));
      expect(find.byKey(const ValueKey('slide_image_loading')), findsOneWidget);
      expect(tester.getSize(find.byType(SlideImage)), const Size(320, 180));

      final picture = await tester.runAsync(() => createTestImage());
      frame.complete(ImageInfo(image: picture!));
      await tester.pump();
      expect(find.byKey(const ValueKey('slide_image_loading')), findsNothing);
      expect(find.byKey(const ValueKey('slide_image_error')), findsNothing);
      expect(tester.widget<RawImage>(find.byType(RawImage)).fit, BoxFit.cover);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a picture that fails shows the error box ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final frame = Completer<ImageInfo>();
      await pumpImage(tester, FakeImage(frame.future));
      frame.completeError(StateError('gone'));
      await tester.pump();
      expect(find.byKey(const ValueKey('slide_image_error')), findsOneWidget);
      expect(find.byKey(const ValueKey('slide_image_loading')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a picture the viewer may not read says so, not a spinner', (
    tester,
  ) async {
    final frame = Completer<ImageInfo>();
    await pumpImage(tester, FakeImage(frame.future));
    frame.completeError(
      NetworkImageLoadException(statusCode: 403, uri: Uri.parse('/x.png')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('slide_image_no_access')), findsOneWidget);
    expect(find.byKey(const ValueKey('slide_image_error')), findsNothing);
    expect(find.byKey(const ValueKey('slide_image_loading')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picture stays out of the semantics tree', (tester) async {
    final handle = tester.ensureSemantics();
    final frame = Completer<ImageInfo>();
    await pumpImage(tester, FakeImage(frame.future));
    frame.completeError(StateError('gone'));
    await tester.pump();
    expect(tester.getSemantics(find.byType(SlideImage)).label, isEmpty);
    handle.dispose();
  });
}
