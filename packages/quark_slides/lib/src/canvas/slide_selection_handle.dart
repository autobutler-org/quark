import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../geometry/slide_handle.dart';
import 'slide_canvas_style.dart';

/// One grip of a selected element: a [SlideCanvasStyle.handleSize] square
/// (a circle for [SlideHandle.rotate]) in the middle of a
/// [SlideCanvasStyle.handleHitSize] box, so it is drawn small but grabbed
/// easily by a finger.
///
/// Keyed `slide_handle_<id>` (see [SlideHandle.keyName]). It shows the mouse
/// cursor for the direction it resizes, turned by the element's [rotation],
/// and draws nothing else: the canvas hit tests and drags it.
class SlideSelectionHandle extends StatelessWidget {
  /// Creates a handle.
  SlideSelectionHandle({
    required this.handle,
    required this.style,
    this.rotation = 0,
  }) : super(key: ValueKey(handle.keyName));

  /// Which handle this is.
  final SlideHandle handle;

  /// Supplies sizes and colors.
  final SlideCanvasStyle style;

  /// The element's rotation in degrees, which turns the resize cursor.
  final double rotation;

  /// The resize cursor for [handle] on an element turned [rotation]
  /// degrees, or a grab cursor for the rotate handle.
  static MouseCursor cursorFor(SlideHandle handle, double rotation) {
    if (!handle.isResize) return SystemMouseCursors.grab;
    final degrees =
        math.atan2(handle.dy.toDouble(), handle.dx.toDouble()) * 180 / math.pi +
            rotation;
    // Fold the direction into [0, 180) and pick the nearest of the four
    // double-headed cursors, 45 degrees apart.
    final sector = ((degrees % 180) / 45).round() % 4;
    return const [
      SystemMouseCursors.resizeLeftRight,
      SystemMouseCursors.resizeUpLeftDownRight,
      SystemMouseCursors.resizeUpDown,
      SystemMouseCursors.resizeUpRightDownLeft,
    ][sector];
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: cursorFor(handle, rotation),
        child: SizedBox.square(
          dimension: style.handleHitSize,
          child: Center(
            child: Container(
              width: style.handleSize,
              height: style.handleSize,
              decoration: BoxDecoration(
                color: style.handleFillColor,
                border: Border.all(color: style.selectionColor, width: 1.5),
                shape: handle.isResize ? BoxShape.rectangle : BoxShape.circle,
              ),
            ),
          ),
        ),
      );
}
