import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the photo grid shows when it has nothing to show, worded for why.
///
/// "No photos yet" would be a lie when the library is merely out of reach, so
/// an unreachable Quark wins over every empty state (#1637).
class PhotosEmptyState extends StatelessWidget {
  /// Creates the empty state.
  const PhotosEmptyState({
    required this.unreachable,
    required this.showingFavorites,
    required this.onRetry,
    required this.onManageHosts,
    this.hostAddress,
    this.albumName,
    this.onUploadPhotos,
    this.onAddPhotosToAlbum,
    super.key,
  });

  /// Whether the last attempt to list photos never reached the Quark.
  final bool unreachable;

  /// Whether the grid is showing favorites, the category or the album, which
  /// get their own hint.
  final bool showingFavorites;

  /// The album the grid is showing, or null for the library.
  final String? albumName;

  /// Tries the Quark again, from the disconnected view.
  final VoidCallback onRetry;

  /// Opens host management, from the disconnected view.
  final VoidCallback onManageHosts;

  /// The Quark the app tried to reach, named in the disconnected view.
  final String? hostAddress;

  /// Starts an upload into the library, from the empty library's own button
  /// (#2009). Null leaves the state as copy alone.
  final VoidCallback? onUploadPhotos;

  /// Starts picking photos for the album on screen, from the empty album's
  /// own button (#2042). Null for an album that cannot be added to — the
  /// system albums the Quark fills itself, and favorites.
  final VoidCallback? onAddPhotosToAlbum;

  @override
  Widget build(BuildContext context) {
    if (unreachable) {
      return QuarkDisconnectedView(
        hostAddress: hostAddress,
        onRetry: onRetry,
        onManageHosts: onManageHosts,
      );
    }
    final albumName = this.albumName;
    if (albumName != null) {
      final onAdd = onAddPhotosToAlbum;
      return EmptyStateWidget(
        icon: QuarkIcons.photo_album_outlined,
        headline: 'No photos yet',
        subtext: showingFavorites
            ? 'Star a photo to add it here.'
            : 'Add photos to "$albumName" from All photos.',
        // The centered copy is where someone is already looking, so it
        // carries the action rather than pointing at a control in the corner
        // (#2042).
        action: (showingFavorites || onAdd == null)
            ? null
            : FilledButton.icon(
                key: const ValueKey('album_empty_add_photos'),
                onPressed: onAdd,
                icon: const Icon(QuarkIcons.add_rounded, size: 18),
                label: const Text('Add photos'),
              ),
      );
    }
    if (showingFavorites) {
      return const EmptyStateWidget(
        icon: QuarkIcons.star_outline_rounded,
        headline: 'No favorites yet',
        subtext: 'Tap ★ on any photo to save it here.',
      );
    }
    final onUpload = onUploadPhotos;
    return EmptyStateWidget(
      icon: QuarkIcons.photo_library_outlined,
      headline: 'No photos yet',
      subtext: 'Photos you upload to Quark will appear here.',
      // A first-time library had nothing to press: uploading lived on an
      // unlabeled "+" in the corner (#2009).
      action: onUpload == null
          ? null
          : FilledButton.icon(
              key: const ValueKey('photos_empty_upload'),
              onPressed: onUpload,
              icon: const Icon(QuarkIcons.add_rounded, size: 18),
              label: const Text('Upload photos'),
            ),
    );
  }
}
