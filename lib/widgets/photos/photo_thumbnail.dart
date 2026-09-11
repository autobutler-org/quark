import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// The picture inside a photo tile: a Quark photo's thumbnail over the
/// network, or a device photo's straight off disk through photo_manager.
///
/// App-side because both sources need something the widget package does not
/// depend on. Pass exactly one of [url] and [asset]; either way a grey box
/// stands in until the picture arrives, or when it never does.
class PhotoThumbnail extends StatelessWidget {
  /// Creates the thumbnail for a Quark photo at [url] or a device [asset].
  const PhotoThumbnail({this.url, this.asset, super.key})
    : assert((url == null) != (asset == null), 'pass a url or an asset');

  /// Where a Quark photo's thumbnail is served.
  final Uri? url;

  /// A photo on this device.
  final AssetEntity? asset;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Colors.grey.shade300);
    final url = this.url;
    if (url != null) {
      return Image.network(
        url.toString(),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
        errorBuilder: (context, error, stack) => placeholder,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: asset!.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        final thumb = snapshot.data;
        if (thumb == null) return placeholder;
        return Image.memory(thumb, fit: BoxFit.cover);
      },
    );
  }
}
