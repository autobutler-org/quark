import 'package:flutter/widgets.dart';

import 'document_table_grid.dart';

/// Places one child at a row and column in `DocumentTableGrid`.
class DocumentTableGridCell extends ParentDataWidget<DocumentTableParentData> {
  /// Creates a placed cell.
  const DocumentTableGridCell({
    required this.row,
    required this.column,
    required this.rowSpan,
    required this.colSpan,
    required super.child,
    super.key,
  });

  /// The zero-based starting row.
  final int row;

  /// The zero-based starting column.
  final int column;

  /// The number of rows occupied.
  final int rowSpan;

  /// The number of columns occupied.
  final int colSpan;

  @override
  Type get debugTypicalAncestorWidgetClass => DocumentTableGrid;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as DocumentTableParentData;
    if (data.row == row &&
        data.column == column &&
        data.rowSpan == rowSpan &&
        data.colSpan == colSpan) {
      return;
    }
    data
      ..row = row
      ..column = column
      ..rowSpan = rowSpan
      ..colSpan = colSpan;
    final parent = renderObject.parent;
    if (parent is RenderObject) parent.markNeedsLayout();
  }
}
