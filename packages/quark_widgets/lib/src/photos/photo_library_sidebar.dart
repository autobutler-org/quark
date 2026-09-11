import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_split_view.dart';
import '../theme/quark_tokens.dart';

/// The sidebar of a photo library: a tile-size slider, an optional category
/// picker, and an album list underneath.
///
/// Built to sit in a [QuarkSplitView], and it asks that widget which shape to
/// take rather than being told, so nothing upstream has to know the
/// breakpoint. Wide, it fills the pane and gives [albums] the remaining
/// height. Collapsed, it sits in a sliver with unbounded height, so it
/// shrink-wraps and never wraps [albums] in an [Expanded] (#1599). [albums]
/// has to shrink-wrap there too.
///
/// The column count is the caller's: [columns] in, [onColumnsChanged] out,
/// already clamped to [minColumns] and [maxColumns].
///
/// Key prefixes: `photo_columns_slider`, `photo_columns_less` (larger
/// photos) and `photo_columns_more` (smaller photos).
///
/// ```dart
/// PhotoLibrarySidebar(
///   columns: controller.columns,
///   minColumns: 1,
///   maxColumns: 8,
///   onColumnsChanged: controller.setColumns,
///   categories: PhotoCategoryList(...),
///   albums: AlbumSidebar(...),
/// );
/// ```
class PhotoLibrarySidebar extends StatelessWidget {
  /// Creates the sidebar.
  const PhotoLibrarySidebar({
    required this.columns,
    required this.minColumns,
    required this.maxColumns,
    required this.onColumnsChanged,
    required this.albums,
    this.categories,
    super.key,
  });

  /// The chosen number of grid columns. Clamped to [minColumns] and
  /// [maxColumns] for display, so a choice made on a wider window survives.
  final int columns;

  /// The fewest columns the slider offers.
  final int minColumns;

  /// The most columns the slider offers.
  final int maxColumns;

  /// Called with the new column count, clamped to [minColumns] and
  /// [maxColumns].
  final ValueChanged<int> onColumnsChanged;

  /// The album list, below everything else.
  final Widget albums;

  /// The category picker under the slider, or null for none.
  final Widget? categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final compact = QuarkSplitView.isCollapsed(context);
    final selected = columns.clamp(minColumns, maxColumns);
    final divisions = maxColumns - minColumns;
    final categories = this.categories;

    // Material, not a colored Container: the list tiles inside paint their
    // background and ink on the nearest Material ancestor, and a plain
    // ColoredBox in between would hide both.
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('photo_columns_less'),
                  onPressed: selected > minColumns
                      ? () => onColumnsChanged(selected - 1)
                      : null,
                  icon: const Icon(QuarkIcons.crop_square_outlined),
                  tooltip: 'Larger photos',
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('photo_columns_slider'),
                    min: minColumns.toDouble(),
                    max: maxColumns.toDouble(),
                    divisions: divisions > 0 ? divisions : null,
                    value: selected.toDouble(),
                    onChanged: (value) => onColumnsChanged(
                      value.round().clamp(minColumns, maxColumns),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('photo_columns_more'),
                  onPressed: selected < maxColumns
                      ? () => onColumnsChanged(selected + 1)
                      : null,
                  icon: const Icon(QuarkIcons.grid_view_outlined),
                  tooltip: 'Smaller photos',
                ),
              ],
            ),
            if (categories != null) ...[
              SizedBox(height: tokens.spacingSm),
              categories,
            ],
            SizedBox(height: tokens.spacingMd),
            if (compact) albums else Expanded(child: albums),
          ],
        ),
      ),
    );
  }
}
