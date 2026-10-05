import 'package:flutter/rendering.dart';

import '../model/slide_element.dart';
import '../model/stroke.dart';
import '../theme/slide_theme.dart';
import 'slide_shape_paths.dart';

/// Paints a [TableElement]'s cell borders in table-local slide units: each
/// edge between two cells, and around the outside, in the stroke
/// `TableElement.edgeAbove` and `TableElement.edgeBefore` give it, dashed as
/// that stroke says. Edges inside a merged area are not drawn.
class SlideTableBorderPainter extends CustomPainter {
  /// Creates a painter for [table]'s borders.
  const SlideTableBorderPainter(this.table, this.theme);

  /// The table whose borders to paint.
  final TableElement table;

  /// The theme a role color resolves against.
  final SlideTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = [
      for (var c = 0; c <= table.columnCount; c++) table.columnStart(c),
    ];
    final ys = [for (var r = 0; r <= table.rowCount; r++) table.rowStart(r)];
    for (var r = 0; r <= table.rowCount; r++) {
      for (var c = 0; c < table.columnCount; c++) {
        _edge(canvas, table.edgeAbove(r, c), Offset(xs[c], ys[r]),
            Offset(xs[c + 1], ys[r]));
      }
    }
    for (var r = 0; r < table.rowCount; r++) {
      for (var c = 0; c <= table.columnCount; c++) {
        _edge(canvas, table.edgeBefore(r, c), Offset(xs[c], ys[r]),
            Offset(xs[c], ys[r + 1]));
      }
    }
  }

  void _edge(Canvas canvas, Stroke? stroke, Offset from, Offset to) {
    if (stroke == null || stroke.width <= 0) return;
    final segment = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
    final intervals = dashIntervals(stroke.dash, stroke.width);
    canvas.drawPath(
      intervals == null ? segment : dashedPath(segment, intervals),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Color(stroke.color.resolve(theme))
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(SlideTableBorderPainter oldDelegate) =>
      oldDelegate.table != table || oldDelegate.theme != theme;
}
