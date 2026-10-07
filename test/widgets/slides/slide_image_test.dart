import 'dart:async';
import 'dart:ui' as ui;

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

/// An animated picture whose stream keeps moving whether or not anyone
/// watches, as `NetworkImage` does on the web: every load starts a new
/// [FakeGifStream] already on frame 0, and the test moves it on.
class FakeGif extends ImageProvider<FakeGif> {
  FakeGif(this.frames);

  final List<ui.Image> frames;

  /// Every stream a load has started, oldest first.
  final streams = <FakeGifStream>[];

  @override
  Future<FakeGif> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(FakeGif key, ImageDecoderCallback decode) {
    final stream = FakeGifStream(frames)..show(0);
    streams.add(stream);
    return stream;
  }
}

/// One playback of a [FakeGif].
class FakeGifStream extends ImageStreamCompleter {
  FakeGifStream(this.frames);

  final List<ui.Image> frames;

  bool _disposed = false;

  /// Moves this playback to frame [index], unless it has been let go.
  void show(int index) {
    if (!_disposed) setImage(ImageInfo(image: frames[index].clone()));
  }

  @override
  void onDisposed() {
    _disposed = true;
    super.onDisposed();
  }
}

/// A picture on a slide shows a placeholder until it loads, the picture once
/// it does, and a broken-picture box when it never will (#1153).
void main() {
  Future<void> pumpImage(
    WidgetTester tester,
    ImageProvider image, {
    bool animate = true,
    bool disableAnimations = false,
    int copies = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < copies; i++)
                  SizedBox(
                    key: ValueKey(i),
                    width: 320,
                    height: 180,
                    child: SlideImage(
                      image: image,
                      fit: BoxFit.cover,
                      animate: animate,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// The frame each picture on screen shows; frame i is 10 + i wide.
  List<int> shownFrames(WidgetTester tester) => [
    for (final raw in tester.widgetList<RawImage>(find.byType(RawImage)))
      raw.image!.width - 10,
  ];

  Future<FakeGif> fakeGif(WidgetTester tester) async => FakeGif([
    for (var i = 0; i < 4; i++)
      (await tester.runAsync(() => createTestImage(width: 10 + i)))!,
  ]);

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

  group('an animated picture (#2866)', () {
    testWidgets('plays its frames in order', (tester) async {
      final gif = await fakeGif(tester);
      await pumpImage(tester, gif, copies: 2);
      for (final frame in [1, 2, 3, 0]) {
        gif.streams.single.show(frame);
        await tester.pump();
        expect(shownFrames(tester), [frame, frame]);
      }
    });

    // Flutter pauses an Image under reduced motion, but the web's stream
    // plays on unseen; a picture built later used to pick up whatever frame
    // that hidden playback had reached.
    testWidgets('holds its first frame under reduced motion', (tester) async {
      final gif = await fakeGif(tester);
      await pumpImage(tester, gif, disableAnimations: true);
      await tester.pump();
      expect(shownFrames(tester), [0]);
      for (final stream in gif.streams) {
        stream.show(2);
      }
      await tester.pump();
      await pumpImage(tester, gif, disableAnimations: true, copies: 2);
      await tester.pump();
      expect(shownFrames(tester), [0, 0]);
    });

    testWidgets('holds its first frame under iOS Reduce Motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final gif = await fakeGif(tester);
      await pumpImage(tester, gif);
      for (final stream in gif.streams) {
        stream.show(3);
      }
      await tester.pump();
      expect(shownFrames(tester), [0]);
    });

    testWidgets('stands still where it is told not to animate', (tester) async {
      final gif = await fakeGif(tester);
      await pumpImage(tester, gif, animate: false);
      for (final stream in gif.streams) {
        stream.show(1);
      }
      await tester.pump();
      expect(shownFrames(tester), [0]);
    });

    testWidgets('a still picture the viewer may not read says so', (
      tester,
    ) async {
      final frame = Completer<ImageInfo>();
      await pumpImage(tester, FakeImage(frame.future), animate: false);
      frame.completeError(
        NetworkImageLoadException(statusCode: 401, uri: Uri.parse('/x.gif')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('slide_image_no_access')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
