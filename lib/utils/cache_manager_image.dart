import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The image at [url], read through [cacheManager] and filed there under
/// [cacheKey].
///
/// A cached copy shows first; when the store revalidates it and fetches a
/// newer one, that replaces it. A failed load leaves the image cache, so the
/// next resolve tries again. On the web the browser fetches and caches it,
/// and [cacheManager] goes unused.
///
/// ```dart
/// Image(image: CacheManagerImage(url, cacheKey: key, cacheManager: store))
/// ```
@immutable
class CacheManagerImage extends ImageProvider<CacheManagerImage> {
  /// The image at [url], under [cacheKey] in [cacheManager].
  const CacheManagerImage(
    this.url, {
    required this.cacheKey,
    required this.cacheManager,
  });

  /// Where the image is fetched from.
  final String url;

  /// What the image is filed under, in [cacheManager] and the image cache.
  final String cacheKey;

  /// The disk store the image is read through.
  final BaseCacheManager cacheManager;

  @override
  Future<CacheManagerImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CacheManagerImage key,
    ImageDecoderCallback decode,
  ) {
    if (kIsWeb) {
      final network = NetworkImage(url);
      return network.loadImage(network, decode);
    }
    return _FrameStreamCompleter(
      cacheManager
          .getFileStream(url, key: cacheKey)
          .where((response) => response is FileInfo)
          .asyncMap((response) async {
            final bytes = await (response as FileInfo).file.readAsBytes();
            final codec = await decode(
              await ui.ImmutableBuffer.fromUint8List(bytes),
            );
            final frame = await codec.getNextFrame();
            codec.dispose();
            return ImageInfo(image: frame.image);
          }),
      onError: () => scheduleMicrotask(
        () => PaintingBinding.instance.imageCache.evict(key),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CacheManagerImage && other.cacheKey == cacheKey;

  @override
  int get hashCode => Object.hash(CacheManagerImage, cacheKey);

  @override
  String toString() => 'CacheManagerImage("$url", cacheKey: "$cacheKey")';
}

/// Shows each image [images] delivers, in turn.
class _FrameStreamCompleter extends ImageStreamCompleter {
  _FrameStreamCompleter(Stream<ImageInfo> images, {required this.onError}) {
    _subscription = images.listen(
      setImage,
      onError: (Object error, StackTrace stack) {
        onError();
        reportError(exception: error, stack: stack);
      },
    );
  }

  late final StreamSubscription<ImageInfo> _subscription;

  /// Called when a load fails.
  final VoidCallback onError;

  @override
  void onDisposed() {
    unawaited(_subscription.cancel());
    super.onDisposed();
  }
}
