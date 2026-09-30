import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../layout/quark_sheet.dart';
import '../models/album_item.dart';
import '../theme/quark_tokens.dart';

/// The body of a bottom sheet that adds one photo to albums, or takes it out.
///
/// Lists the whole album tree flat, each sub-album indented under its parent,
/// with a check on every album the photo is already in. Membership is the
/// caller's: [memberAlbumIds] in, [onToggle] out, and the caller decides
/// whether a tap adds or removes. Show it with [showQuarkSheet], which gives
/// it its title, close button and height cap (#2585).
///
/// With no albums to list, the sheet offers to make one rather than telling
/// the user to go and do it somewhere else (#2041) — pass [onCreateAlbum].
///
/// Key prefix: `add_to_album_<id>` on each album row, plus
/// `add_to_album_create` on the create action.
///
/// ```dart
/// showQuarkSheet<void>(
///   context,
///   title: 'Add to album',
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
    this.onCreateAlbum,
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

  /// Makes a new album to add this photo to. Null leaves the empty state as
  /// copy, for a caller that cannot create one.
  final VoidCallback? onCreateAlbum;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: const Center(child: QuarkLoader()),
      );
    }
    if (error != null) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: Text(error, textAlign: TextAlign.center),
      );
    }
    if (albums.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No albums yet'),
            if (onCreateAlbum != null) ...[
              SizedBox(height: tokens.spacingMd),
              FilledButton.icon(
                key: const ValueKey('add_to_album_create'),
                onPressed: onCreateAlbum,
                icon: const Icon(QuarkIcons.add_rounded, size: 18),
                label: const Text('Create album'),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (album, depth) in AlbumItem.depthFirst(albums))
          ListTile(
            key: ValueKey('add_to_album_${album.id}'),
            contentPadding: EdgeInsetsDirectional.only(
              start: tokens.spacingMd * depth,
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
            subtitle: Text(album.photoCountLabel),
            onTap: () => onToggle(album),
          ),
      ],
    );
  }
}
