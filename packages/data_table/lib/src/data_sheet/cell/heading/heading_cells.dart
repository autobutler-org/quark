import 'package:flutter/material.dart';

import '../../filter/column_filter_button.dart';
import '../cell.dart' show kRangeTintAlpha;
import 'header_resize_handle.dart';

const double kGutterWidth = 48.0;
const double kHeaderHeight = 28.0;
const double kDefaultColumnWidth = 100.0;
const double kDefaultRowHeight = 40.0;
const double kMinColumnWidth = 24.0;
const double kMinRowHeight = 24.0;

/// How thick a header's resize handle is at rest, for a mouse.
const double kResizeHandleSize = 8.0;

/// How thick a selected header's resize handle grows, for a finger.
const double kTouchResizeHandleSize = 24.0;

/// How thick the line between frozen and scrolling panes is.
const double kFrozenDividerThickness = 2.0;

/// The most of the grid's width or height frozen panes may cover; past it
/// they are clipped so the scrolling pane always keeps some room.
const double kMaxFrozenFraction = 0.75;

/// A column header narrower than this hides its filter button unless the
/// column is filtered, so the letter keeps its room.
const double kMinFilterButtonColumnWidth = 48.0;

/// The fill of a column or row header: tinted with the tertiary color while
/// its column is filtered, and with the primary color while its column or row
/// is selected.
Color headerColor(ColorScheme cs, bool isSelected, {bool isFiltered = false}) {
  var color = cs.surfaceContainerHighest;
  if (isFiltered) {
    color = Color.alphaBlend(
      cs.tertiary.withValues(alpha: kRangeTintAlpha),
      color,
    );
  }
  if (isSelected) {
    color = Color.alphaBlend(
      cs.primary.withValues(alpha: kRangeTintAlpha),
      color,
    );
  }
  return color;
}

/// The blank cell where the column header row meets the row-number gutter. This file also holds the column header
/// and row number cells.
class HeaderCornerCell extends StatelessWidget {
  const HeaderCornerCell({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: kGutterWidth,
      height: kHeaderHeight,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.2)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column header cell with right-edge resize handle
// ---------------------------------------------------------------------------

/// A column's letter header, with a [HeaderResizeHandle] on its right edge
/// and, when [onFilter] is set, a [ColumnFilterButton] beside it.
///
/// A filtered column's header is tinted and its funnel filled.
class ColumnHeaderCell extends StatelessWidget {
  final String label;

  /// Called when a drag on the resize handle starts.
  final VoidCallback onResizeStart;
  final void Function(double delta) onResizeDelta;
  final void Function() onAutoSize;

  /// The key for the resize handle, such as `ValueKey('col_resize_0')`.
  final Key? resizeHandleKey;

  /// Whether this header's column is part of the selected range.
  final bool isSelected;

  /// Called when the header is clicked, to select its whole column.
  final VoidCallback? onSelect;

  /// Whether a filter on this column is hiding rows.
  final bool isFiltered;

  /// The key for the filter button, such as `ValueKey('col_filter_0')`.
  final Key? filterButtonKey;

  /// The filter button's tooltip.
  final String filterTooltip;

  /// Called with the filter button's global bounds when it is pressed; no
  /// filter button is shown when null.
  final ValueChanged<Rect>? onFilter;

  const ColumnHeaderCell({
    super.key,
    required this.label,
    required this.onResizeStart,
    required this.onResizeDelta,
    required this.onAutoSize,
    this.resizeHandleKey,
    this.isSelected = false,
    this.onSelect,
    this.isFiltered = false,
    this.filterButtonKey,
    this.filterTooltip = 'Filter',
    this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onFilter = this.onFilter;
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          child: Container(
            height: kHeaderHeight,
            decoration: BoxDecoration(
              color: headerColor(cs, isSelected, isFiltered: isFiltered),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.clip,
            ),
          ),
        ),
        if (onFilter != null)
          Positioned(
            right: HeaderResizeHandle.thickness(expanded: isSelected),
            top: 0,
            bottom: 0,
            width: ColumnFilterButton.size,
            child: Center(
              child: ColumnFilterButton(
                key: filterButtonKey,
                isActive: isFiltered,
                tooltip: filterTooltip,
                onPressed: onFilter,
              ),
            ),
          ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: HeaderResizeHandle.thickness(expanded: isSelected),
          child: HeaderResizeHandle(
            key: resizeHandleKey,
            axis: Axis.horizontal,
            expanded: isSelected,
            onResizeStart: onResizeStart,
            onResizeDelta: onResizeDelta,
            onAutoFit: onAutoSize,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Row number cell (left gutter) with bottom-edge resize handle
// ---------------------------------------------------------------------------

/// A row's number in the left gutter, with a [HeaderResizeHandle] on its
/// bottom edge.
class RowNumberCell extends StatelessWidget {
  final int number;
  final double height;

  /// Called when a drag on the resize handle starts.
  final VoidCallback onResizeStart;
  final void Function(double delta) onResizeDelta;
  final void Function() onAutoSize;

  /// The key for the resize handle, such as `ValueKey('row_resize_0')`.
  final Key? resizeHandleKey;

  /// Whether this header's row is part of the selected range.
  final bool isSelected;

  /// Called when the header is clicked, to select its whole row.
  final VoidCallback? onSelect;

  const RowNumberCell({
    super.key,
    required this.number,
    required this.height,
    required this.onResizeStart,
    required this.onResizeDelta,
    required this.onAutoSize,
    this.resizeHandleKey,
    this.isSelected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          child: Container(
            width: kGutterWidth,
            height: height,
            decoration: BoxDecoration(
              color: headerColor(cs, isSelected),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: HeaderResizeHandle.thickness(expanded: isSelected),
          child: HeaderResizeHandle(
            key: resizeHandleKey,
            axis: Axis.vertical,
            expanded: isSelected,
            onResizeStart: onResizeStart,
            onResizeDelta: onResizeDelta,
            onAutoFit: onAutoSize,
          ),
        ),
      ],
    );
  }
}
