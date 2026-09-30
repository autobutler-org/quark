import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../layout/quark_sheet.dart';
import '../models/album_item.dart';
import '../theme/quark_tokens.dart';

/// The body of a bottom sheet for choosing the album to add photos to.
///
/// Lists the whole album tree flat, each sub-album indented under its parent.
/// It never loads: the albums, [isLoading] and [error] come in, and the
/// caller loads again when [onRetry] fires. Show it with [showQuarkSheet],
/// which gives it its title, close button and height cap (#2585). Its close
/// button leaves the selection behind the sheet alone; the selection bar owns
/// Cancel (#2060).
///
/// Key prefixes: `album_picker_<id>` on each album row,
/// `album_picker_retry` on the retry button, rendered only with an [error],
/// and `album_picker_create` on the create action.
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
    required this.onRetry,
    this.isLoading = false,
    this.error,
    this.onCreateAlbum,
    super.key,
  });

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

  /// Makes a new album to put these photos in. Null leaves the empty state as
  /// copy, for a caller that cannot create one.
  final VoidCallback? onCreateAlbum;

  @override
  Widget build(BuildContext context) {
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
                key: const ValueKey('album_picker_create'),
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
            key: ValueKey('album_picker_${album.id}'),
            contentPadding: EdgeInsetsDirectional.only(
              start: tokens.spacingMd * depth,
            ),
            leading: const Icon(QuarkIcons.photo_album_outlined),
            title: Text(album.name),
            subtitle: Text(album.photoCountLabel),
            onTap: () => onPicked(album),
          ),
      ],
    );
  }
}
