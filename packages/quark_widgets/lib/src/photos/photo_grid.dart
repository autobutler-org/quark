import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/quark_loader.dart';
import '../models/photo_grid_section.dart';
import '../models/photo_item.dart';
import '../theme/quark_tokens.dart';
import 'photo_grid/photo_grid_drag_selection.dart';
import 'photo_grid/photo_grid_drag_target.dart';
import 'photo_grid/photo_grid_section_header.dart';
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
/// [onMenu] gives every remote photo a menu outside selection mode — a
/// button, a right-click and, unless [longPressOpensMenu] is off, a long
/// press, which then no longer calls [onLongPress]. A device photo has
/// nothing on the server to act on, so it gets none. See
/// [PhotoGridTile.onMenu].
///
/// [sections] splits [photos] into consecutive runs, each under a
/// [PhotoGridSectionHeader] that pins to the top of the viewport while its
/// run scrolls past. Every run is its own lazy grid, so only the visible
/// tiles are built however many sections there are. Indices in callbacks
/// still count across the whole of [photos].
///
/// Many photos take one gesture (#4171), and the grid only reports it; the
/// caller decides what ends up selected:
///
/// - A shift-click calls [onRangeSelect] instead of [onTap], for the caller
///   to select from the photo picked last to this one.
/// - A mouse drag that starts on a tile is a rubber band: the tiles in the
///   rows and columns between where it started and the pointer.
/// - A long press that keeps going, on a phone, covers every tile between
///   the pressed one and the finger, in grid order. A swipe that does not
///   follow a long press still scrolls.
///
/// A drag calls [onDragSelectStart], then [onDragSelectUpdate] with every
/// index it covers each time that changes, then [onDragSelectEnd]. Held near
/// the top or bottom of the scroll view, it scrolls. It only covers loaded
/// tiles. Without [onDragSelectUpdate] a drag selects nothing.
///
/// Key prefixes: `photo_grid` on the grid, `photo_grid_section_<id>` on each
/// section header, `photo_grid_loading_more` on the trailing spinner cell,
/// and every tile's own `photo_tile_<id>`,
/// `photo_tile_check_<id>` and `photo_tile_menu_<id>`.
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
///       onRangeSelect: (index) => controller.selectRangeTo(index),
///       onDragSelectStart: controller.beginDragSelection,
///       onDragSelectUpdate: controller.updateDragSelection,
///       onDragSelectEnd: controller.endDragSelection,
///     ),
///   ],
/// );
/// ```
class PhotoGrid extends StatefulWidget {
  /// Creates a grid of [photos].
  const PhotoGrid({
    required this.photos,
    required this.crossAxisCount,
    required this.emptyState,
    required this.thumbnailBuilder,
    required this.onTap,
    required this.onLongPress,
    this.onDoubleTap,
    this.onMenu,
    this.onRangeSelect,
    this.onDragSelectStart,
    this.onDragSelectUpdate,
    this.onDragSelectEnd,
    this.sections,
    this.longPressOpensMenu = true,
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

  /// Called with a tile's index and the global position to open its menu at.
  /// Offered on remote photos outside [selectionMode] only. Null gives the
  /// tiles no menu.
  final void Function(int index, Offset globalPosition)? onMenu;

  /// Called with the index of a tile clicked or tapped with Shift held,
  /// instead of [onTap]. Null leaves a shift-click a plain [onTap].
  final ValueChanged<int>? onRangeSelect;

  /// Called when a drag starts selecting, before its first
  /// [onDragSelectUpdate].
  final VoidCallback? onDragSelectStart;

  /// Called with every index the running drag covers, in order, whenever
  /// that changes. It holds the whole of what the drag covers, so a drag
  /// that turns back leaves tiles out it reported before. Null turns drag
  /// selection off.
  final ValueChanged<List<int>>? onDragSelectUpdate;

  /// Called when the pointer of a selecting drag lifts.
  final VoidCallback? onDragSelectEnd;

  /// Whether a long press opens a tile's menu rather than calling
  /// [onLongPress]. See [PhotoGridTile.longPressOpensMenu].
  final bool longPressOpensMenu;

  /// Splits [photos], in order, into runs with a pinned header each. Their
  /// counts must add up to the length of [photos]. Null or empty draws one
  /// grid with no headers.
  final List<PhotoGridSection>? sections;

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
  State<PhotoGrid> createState() => PhotoGridState();
}

/// The state of a [PhotoGrid]: the drag selection that follows a pointer
/// across its tiles, which outlives a rebuild mid-drag.
class PhotoGridState extends State<PhotoGrid> {
  final PhotoGridDragSelection _drag = PhotoGridDragSelection();

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PhotoGrid(
      :photos,
      :crossAxisCount,
      :emptyState,
      :thumbnailBuilder,
      :onTap,
      :onLongPress,
      :longPressOpensMenu,
      :selectedIds,
      :selectionMode,
      :isLoading,
      :error,
      :hasMore,
      :isLoadingMore,
      :onDoubleTap,
      :onMenu,
      :onRangeSelect,
      :sections,
    ) = widget;
    final gap = QuarkTokens.of(context).spacingXs / 2;

    if (isLoading && photos.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: QuarkLoader()),
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

    final sectionStarts = <int>[];
    var counted = 0;
    for (final section in sections ?? const <PhotoGridSection>[]) {
      sectionStarts.add(counted);
      counted += section.count;
    }
    _drag.configure(
      crossAxisCount: crossAxisCount,
      photoCount: photos.length,
      sectionStarts: sectionStarts,
      scrollable: Scrollable.maybeOf(context),
      viewId: View.of(context).viewId,
      onStart: widget.onDragSelectStart,
      onUpdate: widget.onDragSelectUpdate,
      onEnd: widget.onDragSelectEnd,
    );
    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: gap,
      mainAxisSpacing: gap,
    );
    const loadingMore = Center(
      key: ValueKey('photo_grid_loading_more'),
      child: Padding(padding: EdgeInsets.all(16), child: QuarkLoader()),
    );

    Widget tile(int index) {
      final photo = photos[index];
      return PhotoGridDragTarget(
        key: ValueKey(photo.id),
        selection: _drag,
        index: index,
        child: PhotoGridTile(
          item: photo,
          isSelected: selectedIds.contains(photo.id),
          selectionMode: selectionMode,
          thumbnailBuilder: thumbnailBuilder,
          onTap: () =>
              onRangeSelect != null && HardwareKeyboard.instance.isShiftPressed
              ? onRangeSelect(index)
              : onTap(index),
          onLongPress: () {
            onLongPress(index);
            _drag.longPressed(index);
          },
          onDoubleTap: onDoubleTap != null && photo.isRemote && !selectionMode
              ? () => onDoubleTap(index)
              : null,
          onMenu: onMenu != null && photo.isRemote && !selectionMode
              ? (position) => onMenu(index, position)
              : null,
          longPressOpensMenu: longPressOpensMenu,
        ),
      );
    }

    if (sections == null || sections.isEmpty) {
      return SliverPadding(
        padding: EdgeInsets.all(gap),
        sliver: SliverGrid(
          key: const ValueKey('photo_grid'),
          gridDelegate: gridDelegate,
          delegate: SliverChildBuilderDelegate(
            (context, index) =>
                index >= photos.length ? loadingMore : tile(index),
            childCount: photos.length + (hasMore ? 1 : 0),
          ),
        ),
      );
    }

    assert(
      sections.fold<int>(0, (sum, s) => sum + s.count) == photos.length,
      'The section counts must add up to the number of photos.',
    );
    final groups = <Widget>[];
    var start = 0;
    for (final section in sections) {
      final first = start;
      start += section.count;
      if (section.count == 0) continue;
      groups.add(
        SliverMainAxisGroup(
          slivers: [
            PinnedHeaderSliver(
              child: PhotoGridSectionHeader(
                key: ValueKey('photo_grid_section_${section.id}'),
                label: section.label,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gap, 0, gap, gap),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => tile(first + i),
                  childCount: section.count,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SliverMainAxisGroup(
      key: const ValueKey('photo_grid'),
      slivers: [
        ...groups,
        if (hasMore) const SliverToBoxAdapter(child: loadingMore),
      ],
    );
  }
}
