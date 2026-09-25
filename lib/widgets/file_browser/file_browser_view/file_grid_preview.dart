import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark/widgets/thumbnails/backfilling_thumbnail.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shimmer/shimmer.dart';

/// Preview slot for a grid tile. Sized by the caller (an [Expanded] that
/// hands it whatever the tile has left over) so every tile lines up without
/// risking an overflow, with the thumbnail replacing the icon only once it
/// decodes.
class FileGridPreview extends StatelessWidget {
  const FileGridPreview({required this.item, super.key});

  final FileNode item;

  @override
  Widget build(BuildContext context) {
    final icon = Center(
      child: QuarkFileIcon(name: item.name, isDir: item.isDir, size: 48),
    );

    final url = FilesService.constructThumbnailUrl(
      item.apiPath,
      serial: item.deviceSerial,
    ).toString();
    return SizedBox(
      width: double.infinity,
      child: !hasServerThumbnail(item)
          ? icon
          : BackfillingThumbnail(
              path: item.apiPath,
              serial: item.deviceSerial,
              builder: (context, generation, onFailed) => CachedNetworkImage(
                imageUrl: url,
                cacheKey: '$url#$generation',
                imageBuilder: (context, imageProvider) =>
                    Image(image: imageProvider, fit: BoxFit.cover),
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: Colors.grey[800]!,
                  highlightColor: Colors.grey[700]!,
                  child: Container(color: Colors.grey[800]),
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
