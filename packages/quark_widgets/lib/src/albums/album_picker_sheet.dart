import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/album_item.dart';
import '../theme/quark_tokens.dart';

/// A draggable bottom sheet for choosing the album to add photos to.
///
/// Lists the whole album tree flat, each sub-album indented under its parent.
/// It never loads: the albums, [isLoading] and [error] come in, and the
/// caller loads again when [onRetry] fires. Show it with
/// `showModalBottomSheet(isScrollControlled: true, ...)`.
///
/// Key prefixes: `album_picker_<id>` on each album row and
/// `album_picker_retry` on the retry button, rendered only with an [error].
///
/// ```dart
/// showModalBottomSheet<AlbumItem>(
///   context: context,
///   isScrollControlled: true,
///   builder: (context) => AlbumPickerSheet(
///     selectedCount: 3,
///     albums: albums,
///     onPicked: (album) => Navigator.of(context).pop(album),
///     onRetry: reload,
///   ),
/// );
/// ```
class AlbumPickerSheet extends StatelessWidget {
  /// Creates the picker for [selectedCount] photos.
  const AlbumPickerSheet({
    required this.selectedCount,
    required this.albums,
    required this.onPicked,
    required this.onRetry,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// How many photos are being added, for the title.
  final int selectedCount;

  /// The root albums, each with its sub-albums.
  final List<AlbumItem> albums;

  /// Called with the album that was tapped.
  final ValueChanged<AlbumItem> onPicked;

  /// Called when the retry button under an [error] is tapped.
  final VoidCallback onRetry;

  /// Whether the albums are loading, which shows a spinner.
  final bool isLoading;

  /// A user-facing message for a load that failed, or null.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Column(
        children: [
          SizedBox(height: tokens.spacingSm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outline,
              borderRadius: BorderRadius.circular(tokens.radiusSm / 2),
            ),
          ),
          SizedBox(height: tokens.spacingSm + tokens.spacingXs),
          Text(
            'Add $selectedCount ${selectedCount == 1 ? 'photo' : 'photos'} '
            'to...',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: tokens.spacingXs),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error, textAlign: TextAlign.center),
                        SizedBox(height: tokens.spacingSm),
                        TextButton(
                          key: const ValueKey('album_picker_retry'),
                          onPressed: onRetry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : albums.isEmpty
                ? const Center(
                    child: Text('No albums — create one in the Photos view'),
                  )
                : ListView(
                    controller: scrollController,
                    children: [
                      for (final (album, depth) in AlbumItem.depthFirst(albums))
                        ListTile(
                          key: ValueKey('album_picker_${album.id}'),
                          contentPadding: EdgeInsets.only(
                            left: tokens.spacingMd * (depth + 1),
                            right: tokens.spacingMd,
                          ),
                          leading: const Icon(QuarkIcons.photo_album_outlined),
                          title: Text(album.name),
                          subtitle: Text('${album.itemCount} photos'),
                          onTap: () => onPicked(album),
                        ),
                    ],
                  ),
          ),
          SizedBox(height: tokens.spacingSm),
        ],
      ),
    );
  }
}
