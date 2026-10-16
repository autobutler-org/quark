import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Wraps [image] so that a picture, once decoded, is what every later widget
/// showing it gets for as long as the image cache keeps it, never a frame
/// decoded from it again (#3366).
///
/// cached_network_image's stream completer asks its codec for a new frame
/// each time a listener arrives after the last one has left, which is what a
/// grid tile scrolled away and back does. The new frame replaces the picture
/// already on screen. On the web both frames are drawn from one `<img>`
/// element, and releasing the first clears that element, so the second
/// painted solid black. This holds one listener on [image]'s completer for
/// the whole life of its own, so that completer never sees its listeners
/// come back. A load that fails is evicted, so the next resolve loads afresh.
///
/// ```dart
/// Image(image: DecodeOnceImage(ResizeImage(provider, width: 400)))
/// ```
class DecodeOnceImage extends ImageProvider<DecodeOnceKey> {
  /// Wraps [image].
  const DecodeOnceImage(this.image);

  /// The provider that fetches and decodes the picture.
  final ImageProvider image;

  @override
  Future<DecodeOnceKey> obtainKey(ImageConfiguration configuration) =>
      // A SynchronousFuture stays synchronous through then, so a picture
      // already in the cache is shown in the same frame.
      image.obtainKey(configuration).then(DecodeOnceKey.new);

  @override
  ImageStreamCompleter loadImage(
    DecodeOnceKey key,
    ImageDecoderCallback decode,
  ) => _DecodeOnceCompleter(
    image.loadImage(key.key, decode),
    onError: () =>
        scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key)),
  );
}

/// The image cache key of a [DecodeOnceImage]: its wrapped provider's key.
@immutable
class DecodeOnceKey {
  /// Wraps the wrapped provider's [key].
  const DecodeOnceKey(this.key);

  /// The wrapped provider's key.
  final Object key;

  @override
  bool operator ==(Object other) => other is DecodeOnceKey && other.key == key;

  @override
  int get hashCode => Object.hash(DecodeOnceKey, key);

  @override
  String toString() => 'DecodeOnceKey($key)';
}

/// Passes on what an inner completer reports, to which it stays subscribed
/// until it is disposed itself.
class _DecodeOnceCompleter extends ImageStreamCompleter {
  _DecodeOnceCompleter(this._inner, {required this.onError}) {
    debugLabel = _inner.debugLabel;
    _listener = ImageStreamListener(
      (image, synchronousCall) => setImage(image),
      onChunk: reportImageChunkEvent,
      onError: (error, stack) {
        onError();
        reportError(exception: error, stack: stack, silent: true);
      },
    );
    _inner.addListener(_listener);
  }

  final ImageStreamCompleter _inner;
  late final ImageStreamListener _listener;

  /// Called when the inner completer reports an error.
  final VoidCallback onError;

  @override
  void onDisposed() {
    _inner.removeListener(_listener);
    super.onDisposed();
  }
}
