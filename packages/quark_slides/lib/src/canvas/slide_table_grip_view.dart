import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../geometry/slide_table_grip.dart';
import 'slide_canvas_style.dart';

/// The widget of one [SlideTableGrip]: a short bar across the line it
/// drags, in the middle of a [SlideCanvasStyle.handleHitSize] box, so it is
/// drawn small but grabbed easily by a finger.
///
/// Keyed `slide_table_column_<index>` or `slide_table_row_<index>` (see
/// [SlideTableGrip.keyName]). It shows a resize cursor along the table's
/// axis, turned by its [rotation], and draws nothing else: the canvas hit
/// tests and drags it.
class SlideTableGripView extends StatelessWidget {
  /// Creates the view of [grip].
  SlideTableGripView({
    required this.grip,
    required this.style,
    this.rotation = 0,
  }) : super(key: ValueKey(grip.keyName));

  /// The grip drawn.
  final SlideTableGrip grip;

  /// Supplies sizes and colors.
  final SlideCanvasStyle style;

  /// The table's rotation in degrees.
  final double rotation;

  @override
  Widget build(BuildContext context) {
    final turned = ((rotation % 180) + 180) % 180;
    final across = turned > 45 && turned < 135;
    final horizontal = grip.isColumn != across;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: SizedBox.square(
        dimension: style.handleHitSize,
        child: Center(
          child: Transform.rotate(
            angle: rotation * math.pi / 180,
            child: Container(
              width: grip.isColumn ? style.handleSize / 2 : style.handleSize,
              height: grip.isColumn ? style.handleSize : style.handleSize / 2,
              decoration: BoxDecoration(
                color: style.handleFillColor,
                border: Border.all(color: style.selectionColor, width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
