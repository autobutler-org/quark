import 'package:material_ui/material_ui.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark/widgets/thumbnails/backfilling_thumbnail.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shimmer/shimmer.dart';

/// Preview slot for a grid tile. The caller gives it a square slot, and the
/// thumbnail fills that square with [BoxFit.cover], replacing the icon only
/// once it decodes.
///
/// The thumbnail is excluded from semantics: the row or tile around it
/// already reads the file's name, and an unlabeled image would only add
/// noise to a screen reader (#2603).
///
/// The thumbnail, and the icon when the file has none, are keyed by
/// [fileThumbnailKey]: the file's device serial and path. The grid reuses a
/// tile's element when the file in that slot changes; a key of the slot's
/// index leaves the previous file's image in place (#3355).
///
/// The picture comes from [ThumbnailCacheManager.image], so it is decoded
/// once and a tile coming back from a viewer or a scroll shows its own
/// picture again (#3355).
class FileGridPreview extends StatelessWidget {
  const FileGridPreview({required this.item, this.backfill, super.key});

  final FileNode item;

  /// The backfill the thumbnail asks; [ThumbnailBackfill.instance] when null.
  final ThumbnailBackfill? backfill;

  @override
  Widget build(BuildContext context) {
    final icon = Center(
      child: QuarkFileIcon(
        kind: fileIconKindForName(item.name, isDir: item.isDir),
        size: 48,
      ),
    );
    final thumbKey = fileThumbnailKey(item);

    final url = FilesService.constructThumbnailUrl(
      item.apiPath,
      serial: item.deviceSerial,
    );
    final placeholder = Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[700]!,
      child: Container(color: Colors.grey[800]),
    );
    return SizedBox(
      width: double.infinity,
      child: !hasServerThumbnail(item)
          ? KeyedSubtree(key: thumbKey, child: icon)
          : BackfillingThumbnail(
              path: item.apiPath,
              serial: item.deviceSerial,
              backfill: backfill,
              // A video no one could render a thumbnail for says why
              // (#3559).
              failedBuilder: (context, issue) => KeyedSubtree(
                key: thumbKey,
                child: QuarkThumbnailUnavailable(
                  name: item.name,
                  kind: fileIconKindForName(item.name),
                  issue: issue,
                  reason: Errors.thumbnailUnavailable(
                    issue,
                    isVideo: fileKindForName(item.name) == FileKind.video,
                  ),
                  label: Errors.thumbnailUnavailableShort(issue),
                  iconSize: 48,
                ),
              ),
              // Each generation is a new element: a failed load is not cached,
              // so the element after a backfill loads afresh under the same
              // cache key.
              builder: (context, generation, onFailed) => KeyedSubtree(
                key: ValueKey('${thumbKey.value}:$generation'),
                child: Image(
                  key: thumbKey,
                  image: ThumbnailCacheManager.image(url),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  excludeFromSemantics: true,
                  frameBuilder: (context, child, frame, synchronous) =>
                      frame == null ? placeholder : child,
                  // A video or HEIC with no thumbnail yet gets one rendered
                  // here and uploaded (#2381); a busy Quark is asked again
                  // (#3349).
                  errorBuilder: (context, error, stack) {
                    onFailed(error);
                    return icon;
                  },
                ),
              ),
            ),
    );
  }
}
