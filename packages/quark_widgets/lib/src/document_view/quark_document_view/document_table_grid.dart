import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The span-aware grid behind a document table.
class DocumentTableGrid extends MultiChildRenderObjectWidget {
  /// Creates a grid with [rowCount] rows and [columnCount] columns.
  const DocumentTableGrid({
    required this.rowCount,
    required this.columnCount,
    required super.children,
    super.key,
  });

  /// The number of logical rows.
  final int rowCount;

  /// The number of equal-width logical columns.
  final int columnCount;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      DocumentTableGridRenderBox(rowCount: rowCount, columnCount: columnCount);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant DocumentTableGridRenderBox renderObject,
  ) {
    renderObject
      ..rowCount = rowCount
      ..columnCount = columnCount;
  }
}

/// Layout coordinates written by `DocumentTableGridCell`.
class DocumentTableParentData extends ContainerBoxParentData<RenderBox> {
  /// The zero-based starting row.
  int row = 0;

  /// The zero-based starting column.
  int column = 0;

  /// The number of rows occupied.
  int rowSpan = 1;

  /// The number of columns occupied.
  int colSpan = 1;
}

/// Lays out a `DocumentTableGrid` after measuring its spanned cells.
class DocumentTableGridRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, DocumentTableParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, DocumentTableParentData> {
  /// Creates the render box for a logical grid size.
  DocumentTableGridRenderBox({required int rowCount, required int columnCount})
    : _rowCount = rowCount,
      _columnCount = columnCount;

  int _rowCount;
  int _columnCount;

  /// Updates the number of logical rows.
  set rowCount(int value) {
    if (_rowCount == value) return;
    _rowCount = value;
    markNeedsLayout();
  }

  /// Updates the number of logical columns.
  set columnCount(int value) {
    if (_columnCount == value) return;
    _columnCount = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! DocumentTableParentData) {
      child.parentData = DocumentTableParentData();
    }
  }

  @override
  void performLayout() {
    if (_rowCount == 0 || _columnCount == 0) {
      size = constraints.smallest;
      return;
    }
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final columnWidth = width / _columnCount;
    final heights = List<double>.filled(_rowCount, 0);

    RenderBox? child = firstChild;
    while (child != null) {
      final data = child.parentData! as DocumentTableParentData;
      child.layout(
        BoxConstraints.tightFor(width: columnWidth * data.colSpan),
        parentUsesSize: true,
      );
      if (data.rowSpan == 1 &&
          data.row < heights.length &&
          heights[data.row] < child.size.height) {
        heights[data.row] = child.size.height;
      }
      child = data.nextSibling;
    }

    child = firstChild;
    while (child != null) {
      final data = child.parentData! as DocumentTableParentData;
      final end = (data.row + data.rowSpan).clamp(0, heights.length);
      if (data.row < end) {
        final current = heights
            .sublist(data.row, end)
            .fold(0.0, (total, height) => total + height);
        if (current < child.size.height) {
          final extra = (child.size.height - current) / (end - data.row);
          for (var row = data.row; row < end; row++) {
            heights[row] += extra;
          }
        }
      }
      child = data.nextSibling;
    }

    final contentHeight = heights.fold(0.0, (total, height) => total + height);
    size = constraints.constrain(Size(width, contentHeight));
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as DocumentTableParentData;
      final end = (data.row + data.rowSpan).clamp(0, heights.length);
      final cellHeight = heights
          .sublist(data.row, end)
          .fold(0.0, (total, height) => total + height);
      child.layout(
        BoxConstraints.tight(Size(columnWidth * data.colSpan, cellHeight)),
      );
      data.offset = Offset(
        columnWidth * data.column,
        heights.take(data.row).fold(0.0, (total, height) => total + height),
      );
      child = data.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
