import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark/widgets/thumbnails/backfilling_thumbnail.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shimmer/shimmer.dart';

/// Every row reserves the same leading slot so titles line up whether the
/// row ends up showing a thumbnail or a file-type icon. The thumbnail is hidden
/// from screen readers: the row's title already names the file.
///
/// The thumbnail, and the icon when the file has none, are keyed by
/// [FileNode.apiPath]. A list reuses the element in a slot; without that key
/// the slot keeps painting the previous file's image until the new URL
/// settles.
class FileListLeading extends StatelessWidget {
  const FileListLeading({required this.item, super.key});

  static const double size = 40;

  final FileNode item;

  @override
  Widget build(BuildContext context) {
    final icon = Center(
      child: QuarkFileIcon(name: item.name, isDir: item.isDir),
    );
    final thumbKey = ValueKey(item.apiPath);

    final url = FilesService.constructThumbnailUrl(
      item.apiPath,
      serial: item.deviceSerial,
      size: 'sm',
    ).toString();
    return SizedBox(
      width: size,
      height: size,
      child: !hasServerThumbnail(item)
          ? KeyedSubtree(key: thumbKey, child: icon)
          : BackfillingThumbnail(
              path: item.apiPath,
              serial: item.deviceSerial,
              builder: (context, generation, onFailed) => CachedNetworkImage(
                key: thumbKey,
                imageUrl: url,
                cacheKey: '$url#$generation',
                // Only the decoded thumbnail replaces the icon; the placeholder
                // and error states fall back to it so nothing shifts.
                imageBuilder: (context, imageProvider) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image(
                    image: imageProvider,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: Colors.grey[800]!,
                  highlightColor: Colors.grey[700]!,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // A video or HEIC with no thumbnail yet gets one rendered
                // here and uploaded (#2381).
                errorWidget: (context, url, error) {
                  onFailed();
                  return icon;
                },
              ),
            ),
    );
  }
}
