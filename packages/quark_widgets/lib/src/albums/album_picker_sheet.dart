import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../layout/quark_sheet.dart';
import '../models/album_item.dart';
import '../theme/quark_tokens.dart';

/// The body of a bottom sheet for choosing albums: the album to add a
/// selection of photos to, or the albums one photo is in.
///
/// Lists the whole album tree flat, each sub-album indented under its parent,
/// with a check on every album in [memberAlbumIds]. It never loads: the
/// albums, [isLoading] and [error] come in, and the caller loads again when
/// [onRetry] fires. Show it with [showQuarkSheet], which gives it its title,
/// close button and height cap (#2585). Its close button leaves the selection
/// behind the sheet alone; the selection bar owns Cancel (#2060).
///
/// What a tap does is the caller's: [onPicked] can pop with the album, or
/// add or remove the photo and leave the sheet open. A sheet that stays open
/// ends in a labeled Done for the user to say they are finished (#2590) —
/// pass [onDone], which usually pops the sheet.
///
/// With no albums to list, the sheet offers to make one rather than telling
/// the user to go and do it somewhere else (#2041) — pass [onCreateAlbum].
///
/// Key prefixes, from [keyPrefix] (`album_picker` by default, `add_to_album`
/// in the app's add-to-album sheet): `<keyPrefix>_<id>` on each album row,
/// `<keyPrefix>_retry` on the retry button, rendered only with an [error]
/// and an [onRetry], `<keyPrefix>_create` on the create action, and
/// `<keyPrefix>_done` on Done.
///
/// ```dart
/// showQuarkSheet<AlbumItem>(
///   context,
///   title: 'Add 3 photos to...',
///   builder: (context) => AlbumPickerSheet(
///     albums: albums,
///     onPicked: (album) => Navigator.of(context).pop(album),
///     onRetry: reload,
///   ),
/// );
/// ```
class AlbumPickerSheet extends StatelessWidget {
  /// Creates the picker over [albums].
  const AlbumPickerSheet({
    required this.albums,
    required this.onPicked,
    this.onRetry,
    this.memberAlbumIds = const {},
    this.isLoading = false,
    this.error,
    this.onCreateAlbum,
    this.onDone,
    this.keyPrefix = 'album_picker',
    super.key,
  });

  /// The root albums, each with its sub-albums.
  final List<AlbumItem> albums;

  /// Called with the album that was tapped.
  final ValueChanged<AlbumItem> onPicked;

  /// Called when the retry button under an [error] is tapped. Null leaves
  /// the button out.
  final VoidCallback? onRetry;

  /// The ids of the albums that get a check, such as every album a photo is
  /// already in.
  final Set<int> memberAlbumIds;

  /// Whether the albums are loading, which shows a spinner.
  final bool isLoading;

  /// A user-facing message for a load that failed, or null.
  final String? error;

  /// Makes a new album to put these photos in. Null leaves the empty state as
  /// copy, for a caller that cannot create one.
  final VoidCallback? onCreateAlbum;

  /// Called when the user taps Done, having finished choosing. Null leaves
  /// the button out.
  final VoidCallback? onDone;

  /// The start of every key in the sheet.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final onRetry = this.onRetry;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: const Center(child: QuarkLoader()),
      );
    }
    if (error != null) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              SizedBox(height: tokens.spacingSm),
              TextButton(
                key: ValueKey('${keyPrefix}_retry'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
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
                key: ValueKey('${keyPrefix}_create'),
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
            key: ValueKey('${keyPrefix}_${album.id}'),
            contentPadding: EdgeInsetsDirectional.only(
              start: tokens.spacingMd * depth,
            ),
            leading: memberAlbumIds.contains(album.id)
                ? Icon(QuarkIcons.check_circle_rounded, color: tokens.primary)
                : const Icon(QuarkIcons.photo_album_outlined),
            title: Text(album.name),
            subtitle: Text(album.photoCountLabel),
            onTap: () => onPicked(album),
          ),
        if (onDone != null) ...[
          SizedBox(height: tokens.spacingMd),
          FilledButton.icon(
            key: ValueKey('${keyPrefix}_done'),
            onPressed: onDone,
            icon: const Icon(QuarkIcons.check_rounded, size: 18),
            label: const Text('Done'),
          ),
        ],
      ],
    );
  }
}
