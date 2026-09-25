import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shimmer/shimmer.dart';

/// Preview slot for a grid tile. The caller gives it a square slot, and the
/// thumbnail fills that square with [BoxFit.cover], replacing the icon only
/// once it decodes.
///
/// The thumbnail, and the icon when the file has none, are keyed by
/// [FileNode.apiPath]. The grid reuses a tile's element when the file in
/// that slot changes; the key makes the image a new element instead of
/// briefly showing the previous file.
class FileGridPreview extends StatelessWidget {
  const FileGridPreview({required this.item, super.key});

  final FileNode item;

  @override
  Widget build(BuildContext context) {
    final icon = Center(
      child: QuarkFileIcon(name: item.name, isDir: item.isDir, size: 48),
    );
    final thumbKey = ValueKey(item.apiPath);

    return SizedBox(
      width: double.infinity,
      child: !hasServerThumbnail(item)
          ? KeyedSubtree(key: thumbKey, child: icon)
          : CachedNetworkImage(
              key: thumbKey,
              imageUrl: FilesService.constructThumbnailUrl(
                item.apiPath,
                serial: item.deviceSerial,
              ).toString(),
              imageBuilder: (context, imageProvider) =>
                  Image(image: imageProvider, fit: BoxFit.cover),
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey[800]!,
                highlightColor: Colors.grey[700]!,
                child: Container(color: Colors.grey[800]),
              ),
              errorWidget: (context, url, error) => icon,
            ),
    );
  }
}
