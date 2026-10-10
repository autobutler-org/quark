import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:quark/widgets/thumbnails/backfilling_thumbnail.dart';

/// The picture inside a photo tile: a Quark photo's thumbnail over the
/// network, or a device photo's straight off disk through photo_manager.
/// A Quark photo's thumbnail is kept on disk by [ThumbnailCacheManager], under
/// a key without the session token, so a cold launch or a new sign-in draws
/// the grid without downloading it again (#1777).
/// A [url] with [DemoPhotosService.assetScheme] names a bundled sample photo,
/// drawn from the asset bundle with no request at all.
///
/// App-side because both sources need something the widget package does not
/// depend on. Pass exactly one of [url] and [asset]; either way a grey box
/// stands in until the picture arrives, or when it never does.
///
/// The picture is excluded from semantics: the photo tile around it is the
/// button a screen reader names, and an unlabeled image inside it would only
/// make the tile announce itself as an image too (#2603).
class PhotoThumbnail extends StatelessWidget {
  /// Creates the thumbnail for a Quark photo at [url] or a device [asset].
  const PhotoThumbnail({
    this.url,
    this.asset,
    this.path,
    this.serial,
    super.key,
  }) : assert((url == null) != (asset == null), 'pass a url or an asset');

  /// Where a Quark photo's thumbnail is served.
  final Uri? url;

  /// The Quark photo's path and device. With them, a HEIC whose thumbnail
  /// the Quark lacks gets one rendered here and uploaded (#2381).
  final String? path;
  final String? serial;

  /// A photo on this device.
  final AssetEntity? asset;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Colors.grey.shade300);
    final url = this.url;
    if (url != null && url.scheme == DemoPhotosService.assetScheme) {
      return Image.asset(
        url.path,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      );
    }
    if (url != null) {
      // Each generation is a new element: a failed load is not cached, so the
      // element after a backfill loads afresh under the same cache key.
      Widget thumbnail(
        BuildContext context,
        int generation,
        VoidCallback onFailed,
      ) => ExcludeSemantics(
        key: ValueKey(generation),
        child: CachedNetworkImage(
          imageUrl: url.toString(),
          cacheKey: ThumbnailCacheManager.keyFor(url),
          cacheManager: ThumbnailCacheManager.instance,
          memCacheWidth: ThumbnailCacheConfig.memCacheWidth,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) {
            onFailed();
            return placeholder;
          },
        ),
      );
      final path = this.path;
      return path == null
          ? thumbnail(context, 0, () {})
          : BackfillingThumbnail(
              path: path,
              serial: serial,
              builder: thumbnail,
            );
    }
    return FutureBuilder<Uint8List?>(
      future: asset!.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        final thumb = snapshot.data;
        if (thumb == null) return placeholder;
        return Image.memory(
          thumb,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        );
      },
    );
  }
}
