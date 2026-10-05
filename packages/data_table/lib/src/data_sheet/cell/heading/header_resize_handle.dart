import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'heading_cells.dart' show kResizeHandleSize, kTouchResizeHandleSize;

/// The drag strip on the trailing edge of a column or row header: drag it to
/// resize, double-click (or double-tap) it to fit the content.
///
/// A column's handle drags along [Axis.horizontal], a row's along
/// [Axis.vertical]. At rest the strip is [kResizeHandleSize] thick, which a
/// mouse can find from its resize cursor. While its column or row is selected
/// ([expanded]) it grows to [kTouchResizeHandleSize] and shows a grip, so on a
/// phone a tap on the header puts a handle under the finger.
///
/// Colors come from the theme's primary color (derived from
/// `QuarkTokens.primary` under `QuarkTheme`). Nothing animates, so reduced
/// motion has nothing to turn off. The tooltip names both gestures; give the
/// widget a [key] such as `ValueKey('col_resize_0')` so a test or a Probe
/// script can reach it.
///
/// ```dart
/// HeaderResizeHandle(
///   key: const ValueKey('col_resize_0'),
///   axis: Axis.horizontal,
///   onResizeStart: controller.beginResize,
///   onResizeDelta: (d) => controller.setColumnWidth(0, width + d),
///   onAutoFit: () => controller.autoSizeColumn(0),
/// )
/// ```
class HeaderResizeHandle extends StatefulWidget {
  /// The direction the handle drags: horizontal for a column, vertical for a
  /// row.
  final Axis axis;

  /// Whether to show the touch-sized grip, used while the header is selected.
  final bool expanded;

  /// Called once when a drag starts, so the whole drag undoes as one step.
  final VoidCallback onResizeStart;

  /// Called with each drag movement, in logical pixels along [axis].
  final ValueChanged<double> onResizeDelta;

  /// Called on a double-click or double-tap, to fit the content.
  final VoidCallback onAutoFit;

  /// Creates a resize handle that drags along [axis].
  const HeaderResizeHandle({
    super.key,
    required this.axis,
    required this.onResizeStart,
    required this.onResizeDelta,
    required this.onAutoFit,
    this.expanded = false,
  });

  /// How thick the handle is, across [axis], for the given [expanded] state.
  static double thickness({required bool expanded}) =>
      expanded ? kTouchResizeHandleSize : kResizeHandleSize;

  @override
  State<HeaderResizeHandle> createState() => _HeaderResizeHandleState();
}

class _HeaderResizeHandleState extends State<HeaderResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final horizontal = widget.axis == Axis.horizontal;
    final active = _hovered || widget.expanded;
    return Tooltip(
      message: horizontal
          ? 'Drag to resize the column, double-click to fit'
          : 'Drag to resize the row, double-click to fit',
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The edge follows the pointer from where it went down, so the
          // drag slop is not lost from the new size.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart:
              horizontal ? (_) => widget.onResizeStart() : null,
          onHorizontalDragUpdate:
              horizontal ? (d) => widget.onResizeDelta(d.delta.dx) : null,
          onVerticalDragStart:
              horizontal ? null : (_) => widget.onResizeStart(),
          onVerticalDragUpdate:
              horizontal ? null : (d) => widget.onResizeDelta(d.delta.dy),
          onDoubleTap: widget.onAutoFit,
          child: Container(
            color: active
                ? cs.primary.withValues(alpha: 0.24)
                : Colors.transparent,
            alignment: Alignment.center,
            child: widget.expanded
                ? Container(
                    width: horizontal ? 4 : 16,
                    height: horizontal ? 16 : 4,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
