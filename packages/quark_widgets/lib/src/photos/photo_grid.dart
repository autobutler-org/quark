import 'package:flutter/material.dart';

import '../models/photo_item.dart';
import '../theme/quark_tokens.dart';
import 'photo_grid_tile.dart';

/// A grid of [PhotoGridTile]s, as a sliver, with its loading, error, empty
/// and loading-more states.
///
/// A sliver rather than a box so it can share one scroll view with a
/// collapsed sidebar above it, which is how `QuarkSplitView` lays out a narrow
/// window. Put it in that widget's `slivers`, or in any `CustomScrollView`.
///
/// It never decides when to load. [isLoading], [error], [hasMore] and
/// [isLoadingMore] come in, and the caller fetches the next page when its
/// scroll view nears the end. The states, in order of precedence:
///
/// - [isLoading] with no photos yet: a centered spinner
/// - [error]: the message, centered
/// - no photos and nothing loading: [emptyState], which the caller words
/// - otherwise the grid, with one more cell holding a small spinner while
///   [hasMore] says there is another page
///
/// Gestures are reported by index into [photos]. [onDoubleTap] is offered on
/// remote photos outside selection mode only, since those are the only ones
/// that can be favorited; everywhere else a single tap fires immediately.
///
/// Key prefixes: `photo_grid` on the grid, `photo_grid_loading_more` on the
/// trailing spinner cell, and every tile's own `photo_tile_<id>` and
/// `photo_tile_check_<id>`.
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     PhotoGrid(
///       photos: controller.photos,
///       crossAxisCount: 4,
///       selectedIds: controller.selectedIds,
///       hasMore: controller.hasMore,
///       emptyState: const Text('No photos yet'),
///       thumbnailBuilder: (context, photo) => Image.network(urlFor(photo)),
///       onTap: open,
///       onLongPress: (index) => controller.select(index),
///     ),
///   ],
/// );
/// ```
class PhotoGrid extends StatelessWidget {
  /// Creates a grid of [photos].
  const PhotoGrid({
    required this.photos,
    required this.crossAxisCount,
    required this.emptyState,
    required this.thumbnailBuilder,
    required this.onTap,
    required this.onLongPress,
    this.onDoubleTap,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.isLoading = false,
    this.error,
    this.hasMore = false,
    this.isLoadingMore = false,
    super.key,
  });

  /// The photos to show, in order.
  final List<PhotoItem> photos;

  /// How many tiles fit across a row. The caller decides from the width it
  /// has and the density the user chose.
  final int crossAxisCount;

  /// What fills the space when there are no photos and nothing is loading.
  final Widget emptyState;

  /// Builds the thumbnail inside each tile.
  final Widget Function(BuildContext context, PhotoItem item) thumbnailBuilder;

  /// Called with the index of the tile that was tapped.
  final ValueChanged<int> onTap;

  /// Called with the index of the tile that was long-pressed.
  final ValueChanged<int> onLongPress;

  /// Called with the index of the tile that was double-tapped. Only remote
  /// photos outside [selectionMode] offer it. Null offers it nowhere.
  final ValueChanged<int>? onDoubleTap;

  /// The [PhotoItem.id]s in the selection.
  final Set<String> selectedIds;

  /// Whether photos are being selected, which every tile draws.
  final bool selectionMode;

  /// Whether the first load is in flight. Shows a spinner only while there
  /// are no photos, so a refresh keeps the current grid on screen.
  final bool isLoading;

  /// A user-facing message for a load that failed, or null.
  final String? error;

  /// Whether another page exists, which appends a spinner cell.
  final bool hasMore;

  /// Whether the next page is in flight. Holds back [emptyState] while it is,
  /// so an empty first page does not flash "nothing here".
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final gap = QuarkTokens.of(context).spacingXs / 2;

    if (isLoading && photos.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(error, textAlign: TextAlign.center)),
      );
    }
    if (photos.isEmpty && !isLoadingMore) {
      return SliverFillRemaining(hasScrollBody: false, child: emptyState);
    }

    final onDoubleTap = this.onDoubleTap;
    return SliverPadding(
      padding: EdgeInsets.all(gap),
      sliver: SliverGrid(
        key: const ValueKey('photo_grid'),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= photos.length) {
            return const Center(
              key: ValueKey('photo_grid_loading_more'),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final photo = photos[index];
          return PhotoGridTile(
            key: ValueKey(photo.id),
            item: photo,
            isSelected: selectedIds.contains(photo.id),
            selectionMode: selectionMode,
            thumbnailBuilder: thumbnailBuilder,
            onTap: () => onTap(index),
            onLongPress: () => onLongPress(index),
            onDoubleTap: onDoubleTap != null && photo.isRemote && !selectionMode
                ? () => onDoubleTap(index)
                : null,
          );
        }, childCount: photos.length + (hasMore ? 1 : 0)),
      ),
    );
  }
}
