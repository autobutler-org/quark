import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' show ClientException;
import 'package:photo_manager/photo_manager.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/widgets/thumbnails/backfilling_thumbnail.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The picture inside a photo tile: a Quark photo's thumbnail over the
/// network, or a device photo's straight off disk through photo_manager.
/// A Quark photo's thumbnail is kept on disk by [ThumbnailCacheManager], under
/// a key without the session token, so a cold launch or a new sign-in draws
/// the grid without downloading it again (#1777), and through
/// [ThumbnailCacheManager.image], so a tile scrolled away and back shows the
/// picture it already decoded rather than a black square (#3366).
/// A [url] with [DemoPhotosService.assetScheme] names a bundled sample photo,
/// drawn from the asset bundle with no request at all.
///
/// App-side because both sources need something the widget package does not
/// depend on. Pass exactly one of [url] and [asset]; either way a gray box
/// stands in until the picture arrives. A Quark photo whose thumbnail will
/// not arrive says why instead (#3509): [QuarkThumbnailUnavailable] for the
/// [ThumbnailIssue] [issueFor] reads from the error — gone, unreadable, or
/// not sent — keyed `photo_thumbnail_<issue>` (`photo_thumbnail_missing`,
/// `photo_thumbnail_unreadable`, `photo_thumbnail_loadFailed`). A busy Quark
/// keeps the gray box while its retries last, and so does a photo whose
/// backfill is still rendering.
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
    this.backfill,
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

  /// The backfill a Quark photo with a [path] asks;
  /// [ThumbnailBackfill.instance] when null.
  final ThumbnailBackfill? backfill;

  /// Why a thumbnail that failed to load with [error] will not show: a 404
  /// or 410 means the Quark has none, any other status or a failed request
  /// that it could not be fetched, and anything else that the bytes it sent
  /// are not a picture.
  static ThumbnailIssue issueFor(Object? error) => switch (error) {
    HttpExceptionWithStatus(statusCode: 404 || 410) => ThumbnailIssue.missing,
    HttpExceptionWithStatus() || ClientException() => ThumbnailIssue.loadFailed,
    _ => ThumbnailIssue.unreadable,
  };

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
      final name = (this.path ?? url.path).split('/').last;
      Widget unavailable(BuildContext context, ThumbnailIssue issue) =>
          KeyedSubtree(
            key: ValueKey('photo_thumbnail_${issue.name}'),
            child: ColoredBox(
              color: QuarkTokens.of(context).card,
              child: QuarkThumbnailUnavailable(
                name: name,
                kind: fileIconKindForName(name),
                issue: issue,
                reason: Errors.thumbnailUnavailable(
                  issue,
                  isVideo: fileKindForName(name) == FileKind.video,
                ),
                label: Errors.thumbnailUnavailableShort(issue),
                iconSize: 32,
              ),
            ),
          );
      // Each generation is a new element: a failed load is not cached, so the
      // element after a backfill loads afresh under the same cache key.
      Widget thumbnail(
        BuildContext context,
        int generation,
        bool Function([Object? error]) onFailed,
      ) => Image(
        key: ValueKey(generation),
        image: ThumbnailCacheManager.image(url),
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, synchronous) =>
            frame == null ? placeholder : child,
        errorBuilder: (context, error, stack) => onFailed(error)
            ? placeholder
            : unavailable(context, issueFor(error)),
      );
      final path = this.path;
      return path == null
          ? thumbnail(context, 0, ([_]) => false)
          : BackfillingThumbnail(
              path: path,
              serial: serial,
              backfill: backfill,
              failedBuilder: unavailable,
              issueFor: issueFor,
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
