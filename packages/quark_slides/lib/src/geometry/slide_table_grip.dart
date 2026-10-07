import 'dart:ui';

import '../model/element_frame.dart';
import '../model/slide_element.dart';
import 'frame_geometry.dart';

/// A grip on a selected table for dragging the line between two of its
/// columns, on the table's top edge, or two of its rows, on its left edge.
///
/// [index] is the column (or row) whose far edge the grip drags: column
/// grip 0 sits between columns 0 and 1. Dragging it resizes that column,
/// and the next one makes up the difference
/// (`SlideDocumentController.setTableColumnWidth`); dragging a row grip
/// makes the row taller or shorter, and the table with it
/// (`SlideDocumentController.setTableRowHeight`).
///
/// Each grip's widget is keyed `slide_table_column_<index>` or
/// `slide_table_row_<index>` (see [keyName]).
class SlideTableGrip {
  /// Creates the grip after column (or, unless [isColumn], row) [index].
  const SlideTableGrip({required this.isColumn, required this.index});

  /// Whether the grip drags a column's right edge rather than a row's
  /// bottom edge.
  final bool isColumn;

  /// The column or row whose far edge the grip drags.
  final int index;

  /// The [ValueKey] value of this grip's widget.
  String get keyName =>
      isColumn ? 'slide_table_column_$index' : 'slide_table_row_$index';

  /// Every grip of [table], whose frame on the slide is [frame], with the
  /// slide point it sits on: one between each two columns on the top edge,
  /// one between each two rows on the left edge.
  static List<(SlideTableGrip, Offset)> gripsOf(
    TableElement table,
    ElementFrame frame,
  ) {
    final half = Offset(frame.width, frame.height) / 2;
    return [
      for (var c = 0; c < table.columnCount - 1; c++)
        (
          SlideTableGrip(isColumn: true, index: c),
          frame.toSlide(Offset(table.columnStart(c + 1), 0) - half),
        ),
      for (var r = 0; r < table.rowCount - 1; r++)
        (
          SlideTableGrip(isColumn: false, index: r),
          frame.toSlide(Offset(0, table.rowStart(r + 1)) - half),
        ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is SlideTableGrip &&
      other.isColumn == isColumn &&
      other.index == index;

  @override
  int get hashCode => Object.hash(isColumn, index);

  @override
  String toString() => 'SlideTableGrip($keyName)';
}
