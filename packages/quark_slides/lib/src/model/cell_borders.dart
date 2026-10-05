import '../format/json_fields.dart';
import 'stroke.dart';
import 'unset.dart';

/// An edge of a table cell.
enum CellSide {
  /// The edge above the cell.
  top,

  /// The edge after the cell, to its right.
  right,

  /// The edge below the cell.
  bottom,

  /// The edge before the cell, to its left.
  left,
}

/// The lines drawn along a table cell's four edges: a [Stroke] for each
/// side, or none.
///
/// Two cells side by side share an edge. The table commands set both
/// cells' sides of it together, and when they disagree anyway the cell
/// above or to the left wins where it has a line (see
/// `TableElement.edgeAbove`).
///
/// In `.qslide` it is the cell's `borders` object, a stroke per side that
/// has one: `{"top": {"color": "theme:text2", "width": 2}}`.
class CellBorders {
  /// Creates the borders of a cell; a side left `null` has no line.
  const CellBorders({
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.extra = const {},
  });

  /// Every side drawn with [stroke].
  const CellBorders.all(Stroke stroke)
      : top = stroke,
        right = stroke,
        bottom = stroke,
        left = stroke,
        extra = const {};

  /// No lines at all.
  static const none = CellBorders();

  /// The line above the cell, or `null`.
  final Stroke? top;

  /// The line to the cell's right, or `null`.
  final Stroke? right;

  /// The line below the cell, or `null`.
  final Stroke? bottom;

  /// The line to the cell's left, or `null`.
  final Stroke? left;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {'top', 'right', 'bottom', 'left'};

  /// The line along [side], or `null`.
  Stroke? operator [](CellSide side) => switch (side) {
        CellSide.top => top,
        CellSide.right => right,
        CellSide.bottom => bottom,
        CellSide.left => left,
      };

  /// A copy with [side]'s line replaced by [stroke], `null` for none.
  CellBorders withSide(CellSide side, Stroke? stroke) => switch (side) {
        CellSide.top => copyWith(top: stroke),
        CellSide.right => copyWith(right: stroke),
        CellSide.bottom => copyWith(bottom: stroke),
        CellSide.left => copyWith(left: stroke),
      };

  /// The borders with rows and columns swapped: top for left and bottom for
  /// right, as transposing a table needs.
  CellBorders get transposed => CellBorders(
        top: left,
        right: bottom,
        bottom: right,
        left: top,
        extra: extra,
      );

  /// Reads borders from their `.qslide` object at [path].
  factory CellBorders.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    Stroke? side(String key) =>
        json[key] == null ? null : Stroke.fromJson(json[key], '$path.$key');
    return CellBorders(
      top: side('top'),
      right: side('right'),
      bottom: side('bottom'),
      left: side('left'),
      extra: unknownFields(json, _known),
    );
  }

  /// The borders as their `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        if (top != null) 'top': top!.toJson(),
        if (right != null) 'right': right!.toJson(),
        if (bottom != null) 'bottom': bottom!.toJson(),
        if (left != null) 'left': left!.toJson(),
      };

  /// Whether no side has a line and nothing unknown is kept.
  bool get isEmpty =>
      top == null &&
      right == null &&
      bottom == null &&
      left == null &&
      extra.isEmpty;

  /// Returns a copy with the given sides replaced; pass `null` to clear
  /// one.
  CellBorders copyWith({
    Object? top = unset,
    Object? right = unset,
    Object? bottom = unset,
    Object? left = unset,
  }) =>
      CellBorders(
        top: identical(top, unset) ? this.top : top as Stroke?,
        right: identical(right, unset) ? this.right : right as Stroke?,
        bottom: identical(bottom, unset) ? this.bottom : bottom as Stroke?,
        left: identical(left, unset) ? this.left : left as Stroke?,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is CellBorders &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(top, right, bottom, left, jsonHash(extra));
}
