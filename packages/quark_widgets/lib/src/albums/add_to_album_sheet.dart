import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/album_item.dart';
import '../theme/quark_tokens.dart';

/// A draggable bottom sheet that adds one photo to albums, or takes it out.
///
/// Lists the whole album tree flat, each sub-album indented under its parent,
/// with a check on every album the photo is already in. Membership is the
/// caller's: [memberAlbumIds] in, [onToggle] out, and the caller decides
/// whether a tap adds or removes. Show it with
/// `showModalBottomSheet(isScrollControlled: true, ...)`.
///
/// Key prefix: `add_to_album_<id>` on each album row.
///
/// ```dart
/// showModalBottomSheet<void>(
///   context: context,
///   isScrollControlled: true,
///   builder: (context) => AddToAlbumSheet(
///     albums: albums,
///     memberAlbumIds: memberIds,
///     onToggle: toggleMembership,
///   ),
/// );
/// ```
class AddToAlbumSheet extends StatelessWidget {
  /// Creates the sheet over [albums].
  const AddToAlbumSheet({
    required this.albums,
    required this.memberAlbumIds,
    required this.onToggle,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// The root albums, each with its sub-albums.
  final List<AlbumItem> albums;

  /// The ids of every album the photo is in, which get a check.
  final Set<int> memberAlbumIds;

  /// Called with the album whose row was tapped.
  final ValueChanged<AlbumItem> onToggle;

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
          const Text(
            'Add to album',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: tokens.spacingSm),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(child: Text(error, textAlign: TextAlign.center))
                : albums.isEmpty
                ? const Center(child: Text('No albums — create one first'))
                : ListView(
                    controller: scrollController,
                    children: [
                      for (final (album, depth) in AlbumItem.depthFirst(albums))
                        ListTile(
                          key: ValueKey('add_to_album_${album.id}'),
                          contentPadding: EdgeInsets.only(
                            left: tokens.spacingMd * (depth + 1),
                            right: tokens.spacingMd,
                          ),
                          leading: Icon(
                            memberAlbumIds.contains(album.id)
                                ? QuarkIcons.check_circle_rounded
                                : QuarkIcons.photo_album_outlined,
                            color: memberAlbumIds.contains(album.id)
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          title: Text(album.name),
                          subtitle: Text('${album.itemCount} photos'),
                          onTap: () => onToggle(album),
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
