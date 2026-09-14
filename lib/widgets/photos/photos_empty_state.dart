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
      return EmptyStateWidget(
        icon: QuarkIcons.photo_album_outlined,
        headline: 'No photos yet',
        subtext: showingFavorites
            ? 'Star a photo to add it here.'
            : 'Add photos to "$albumName" from All photos.',
      );
    }
    if (showingFavorites) {
      return const EmptyStateWidget(
        icon: QuarkIcons.star_outline_rounded,
        headline: 'No favorites yet',
        subtext: 'Tap ★ on any photo to save it here.',
      );
    }
    return const EmptyStateWidget(
      icon: QuarkIcons.photo_library_outlined,
      headline: 'No photos yet',
      subtext: 'Photos you upload to Quark will appear here.',
    );
  }
}
