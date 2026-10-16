import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark/widgets/thumbnails/backfilling_thumbnail.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shimmer/shimmer.dart';

/// Every row reserves the same leading slot so titles line up whether the
/// row ends up showing a thumbnail or a file-type icon.
///
/// The thumbnail is excluded from semantics: the row or tile around it
/// already reads the file's name, and an unlabeled image would only add
/// noise to a screen reader (#2603).
///
/// The thumbnail, and the icon when the file has none, are keyed by
/// [fileThumbnailKey]. A list reuses the element in a slot; without that key
/// the slot keeps painting the previous file's image until the new URL
/// settles.
///
/// The picture comes from [ThumbnailCacheManager.image], so it is decoded
/// once. The list leaves the screen whenever a file opens in a viewer, and a
/// thumbnail decoded again when it came back painted another row's picture
/// on the web (#3355).
class FileListLeading extends StatelessWidget {
  const FileListLeading({required this.item, super.key});

  static const double size = 40;

  final FileNode item;

  @override
  Widget build(BuildContext context) {
    final icon = Center(
      child: QuarkFileIcon(name: item.name, isDir: item.isDir),
    );
    final thumbKey = fileThumbnailKey(item);

    final url = FilesService.constructThumbnailUrl(
      item.apiPath,
      serial: item.deviceSerial,
      size: 'sm',
    );
    final placeholder = Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[700]!,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: !hasServerThumbnail(item)
          ? KeyedSubtree(key: thumbKey, child: icon)
          : BackfillingThumbnail(
              path: item.apiPath,
              serial: item.deviceSerial,
              // Each generation is a new element: a failed load is not cached,
              // so the element after a backfill loads afresh under the same
              // cache key.
              builder: (context, generation, onFailed) => KeyedSubtree(
                key: ValueKey(generation),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image(
                    key: thumbKey,
                    image: ThumbnailCacheManager.image(url),
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    excludeFromSemantics: true,
                    // Only the decoded thumbnail replaces the icon; the
                    // placeholder and error states fall back to it so nothing
                    // shifts.
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
            ),
    );
  }
}
