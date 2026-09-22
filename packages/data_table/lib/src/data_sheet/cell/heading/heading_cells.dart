import 'package:flutter/material.dart';

const double kGutterWidth = 48.0;
const double kHeaderHeight = 28.0;
const double kDefaultColumnWidth = 100.0;
const double kDefaultRowHeight = 40.0;
const double kMinColumnWidth = 24.0;
const double kMinRowHeight = 24.0;
const double kResizeHandleSize = 4.0;

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

class ColumnHeaderCell extends StatefulWidget {
  final String label;
  final void Function(double delta) onResizeDelta;
  final void Function() onAutoSize;

  const ColumnHeaderCell({
    super.key,
    required this.label,
    required this.onResizeDelta,
    required this.onAutoSize,
  });

  @override
  State<ColumnHeaderCell> createState() => _ColumnHeaderCellState();
}

class _ColumnHeaderCellState extends State<ColumnHeaderCell> {
  bool _handleHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          height: kHeaderHeight,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.2)),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
            overflow: TextOverflow.clip,
          ),
        ),
        // Right-edge resize handle
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: kResizeHandleSize,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            onEnter: (_) => setState(() => _handleHovered = true),
            onExit: (_) => setState(() => _handleHovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => widget.onResizeDelta(d.delta.dx),
              onDoubleTap: widget.onAutoSize,
              child: Container(
                color: _handleHovered
                    ? cs.primary.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Row number cell (left gutter) with bottom-edge resize handle
// ---------------------------------------------------------------------------

class RowNumberCell extends StatefulWidget {
  final int number;
  final double height;
  final void Function(double delta) onResizeDelta;
  final void Function() onAutoSize;

  const RowNumberCell({
    super.key,
    required this.number,
    required this.height,
    required this.onResizeDelta,
    required this.onAutoSize,
  });

  @override
  State<RowNumberCell> createState() => _RowNumberCellState();
}

class _RowNumberCellState extends State<RowNumberCell> {
  bool _handleHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          width: kGutterWidth,
          height: widget.height,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.2)),
          ),
          alignment: Alignment.center,
          child: Text(
            '${widget.number}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ),
        // Bottom-edge resize handle
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: kResizeHandleSize,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            onEnter: (_) => setState(() => _handleHovered = true),
            onExit: (_) => setState(() => _handleHovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => widget.onResizeDelta(d.delta.dy),
              onDoubleTap: widget.onAutoSize,
              child: Container(
                color: _handleHovered
                    ? cs.primary.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
