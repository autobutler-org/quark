import 'dart:math' as math;

/// A rectangle of table cells, from [top], [left] to [bottom], [right],
/// every bound inclusive and counted from 0.
///
/// ```dart
/// const CellRange.single(0, 0); // the first cell
/// CellRange.spanning((row: 2, column: 3), (row: 0, column: 1)); // rows 0–2, columns 1–3
/// ```
class CellRange {
  /// Creates the range from [top], [left] to [bottom], [right].
  const CellRange({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  })  : assert(top >= 0 && left >= 0),
        assert(bottom >= top && right >= left);

  /// The one cell at [row], [column].
  const CellRange.single(int row, int column)
      : this(top: row, left: column, bottom: row, right: column);

  /// The smallest range holding both [a] and [b], in either order — what a
  /// drag from one cell to another selects.
  factory CellRange.spanning(
    ({int row, int column}) a,
    ({int row, int column}) b,
  ) =>
      CellRange(
        top: math.min(a.row, b.row),
        left: math.min(a.column, b.column),
        bottom: math.max(a.row, b.row),
        right: math.max(a.column, b.column),
      );

  /// The first row.
  final int top;

  /// The first column.
  final int left;

  /// The last row.
  final int bottom;

  /// The last column.
  final int right;

  /// How many rows the range covers.
  int get rowCount => bottom - top + 1;

  /// How many columns the range covers.
  int get columnCount => right - left + 1;

  /// Whether the range is a single cell.
  bool get isSingle => top == bottom && left == right;

  /// Whether the cell at [row], [column] is inside the range.
  bool contains(int row, int column) =>
      row >= top && row <= bottom && column >= left && column <= right;

  /// Whether this range and [other] share a cell.
  bool overlaps(CellRange other) =>
      other.top <= bottom &&
      other.bottom >= top &&
      other.left <= right &&
      other.right >= left;

  /// The smallest range holding this one and [other].
  CellRange union(CellRange other) => CellRange(
        top: math.min(top, other.top),
        left: math.min(left, other.left),
        bottom: math.max(bottom, other.bottom),
        right: math.max(right, other.right),
      );

  /// The range with rows and columns swapped.
  CellRange get transposed =>
      CellRange(top: left, left: top, bottom: right, right: bottom);

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
  String toString() => 'CellRange($top, $left – $bottom, $right)';
}
