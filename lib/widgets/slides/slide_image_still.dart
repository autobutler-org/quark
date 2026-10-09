import 'dart:async';

import 'package:flutter/widgets.dart';

/// The first frame of [image], and only that frame: an animated GIF drawn
/// through it stands still on frame 0.
///
/// It loads [image] on its own rather than through the image cache, so it
/// gets a playback of its own that starts at the first frame, takes that
/// frame, and lets the playback go. Sharing the cached stream would hand it
/// whatever frame the stream had reached, and on the web that stream keeps
/// playing even while every picture showing it is paused (#2866).
///
/// A picture that fails to load fails here the same way, so a `401` still
/// reads as no access.
///
/// ```dart
/// Image(image: SlideStillImage(NetworkImage(url)));
/// ```
class SlideStillImage extends ImageProvider<SlideStillImageKey> {
  /// Holds the first frame of [image].
  const SlideStillImage(this.image);

  /// The picture whose first frame is drawn.
  final ImageProvider<Object> image;

  @override
  Future<SlideStillImageKey> obtainKey(ImageConfiguration configuration) =>
      image.obtainKey(configuration).then(SlideStillImageKey.new);

  @override
  ImageStreamCompleter loadImage(
    SlideStillImageKey key,
    ImageDecoderCallback decode,
  ) {
    final first = Completer<ImageInfo>();
    final playback = image.loadImage(key.source, decode);
    late final ImageStreamListener listener;
    void finish(void Function() complete) {
      playback.removeListener(listener);
      if (!first.isCompleted) complete();
    }

    listener = ImageStreamListener(
      (info, _) => finish(() => first.complete(info)),
      onError: (error, stack) =>
          finish(() => first.completeError(error, stack)),
    );
    playback.addListener(listener);
    return OneFrameImageStreamCompleter(first.future);
  }

  @override
  bool operator ==(Object other) =>
      other is SlideStillImage && other.image == image;

  @override
  int get hashCode => Object.hash(SlideStillImage, image);
}

/// The cache key of a [SlideStillImage]: its picture's own key, kept apart
/// from that picture's moving stream.
@immutable
class SlideStillImageKey {
  /// Wraps the key [source] of the picture.
  const SlideStillImageKey(this.source);

  /// The key of the picture the still is taken from.
  final Object source;

  @override
  bool operator ==(Object other) =>
      other is SlideStillImageKey && other.source == source;

  @override
  int get hashCode => Object.hash(SlideStillImageKey, source);
}
