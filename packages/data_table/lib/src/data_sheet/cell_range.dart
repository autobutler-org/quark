import 'package:flutter/foundation.dart';

import 'cell/heading/util.dart';

/// An inclusive rectangle of cells, from [top]/[left] to [bottom]/[right].
///
/// Ranges are always normalized — `top <= bottom` and `left <= right` — no
/// matter which corner the selection started from, so callers can iterate
/// rows and columns without checking direction.
///
/// ```dart
/// final range = CellRange.fromCorners(8, 3, 1, 1);
/// range.label; // 'B2:D9'
/// ```
@immutable
class CellRange {
  /// First row of the range (0-based, inclusive).
  final int top;

  /// First column of the range (0-based, inclusive).
  final int left;

  /// Last row of the range (0-based, inclusive).
  final int bottom;

  /// Last column of the range (0-based, inclusive).
  final int right;

  /// Creates a range from already-normalized bounds.
  const CellRange({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  })  : assert(top <= bottom),
        assert(left <= right);

  /// Creates the range spanning two opposite corners, in either order.
  factory CellRange.fromCorners(int rowA, int colA, int rowB, int colB) =>
      CellRange(
        top: rowA < rowB ? rowA : rowB,
        left: colA < colB ? colA : colB,
        bottom: rowA < rowB ? rowB : rowA,
        right: colA < colB ? colB : colA,
      );

  /// Number of rows the range covers.
  int get rowCount => bottom - top + 1;

  /// Number of columns the range covers.
  int get colCount => right - left + 1;

  /// True when the range is exactly one cell.
  bool get isSingleCell => top == bottom && left == right;

  /// True when ([row], [col]) lies inside the range.
  bool contains(int row, int col) =>
      row >= top && row <= bottom && col >= left && col <= right;

  /// True when [row] is one of the range's rows.
  bool containsRow(int row) => row >= top && row <= bottom;

  /// True when [col] is one of the range's columns.
  bool containsCol(int col) => col >= left && col <= right;

  /// The A1-style address: `B2` for one cell, `B2:D9` for a rectangle.
  String get label {
    final start = '${columnLabel(left)}${top + 1}';
    if (isSingleCell) return start;
    return '$start:${columnLabel(right)}${bottom + 1}';
  }

  @override
  bool operator ==(Object other) =>
      other is CellRange &&
      other.top == top &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right;

  @override
  int get hashCode => Object.hash(top, left, bottom, right);

  @override
  String toString() => 'CellRange($label)';
}
