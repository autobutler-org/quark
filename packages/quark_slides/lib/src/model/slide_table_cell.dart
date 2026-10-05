import '../format/json_fields.dart';
import '../format/qslide_format_exception.dart';
import 'cell_borders.dart';
import 'slide_color.dart';
import 'slide_element.dart';
import 'text_paragraph.dart';
import 'unset.dart';

/// One cell of a `TableElement` — named so as not to collide with Flutter's
/// `TableCell` widget: rich text — the same [paragraphs] of
/// styled runs a [TextBox] holds — held to its [anchor] edge, a [fill], and
/// the [borders] along its edges.
///
/// A cell with a [rowSpan] or [colSpan] above 1 is the anchor of a merged
/// area: its text, fill and anchor fill the whole rectangle of
/// [rowSpan] × [colSpan] cells from it, down and to the right. The cells it
/// covers stay in the grid, so it is always rectangular, but are not drawn;
/// unmerging brings them back.
///
/// In `.qslide` a cell is an object; every field is optional, so a blank
/// cell is `{}`:
///
/// ```json
/// {"paragraphs": [{"runs": [{"text": "Q3"}]}], "fill": "theme:accent2",
///  "anchor": "middle", "rowSpan": 2,
///  "borders": {"bottom": {"color": "#000000", "width": 2}}}
/// ```
class SlideTableCell {
  /// Creates a cell.
  const SlideTableCell({
    this.paragraphs = const [],
    this.fill,
    this.borders = CellBorders.none,
    this.anchor = TextAnchor.top,
    this.rowSpan = 1,
    this.colSpan = 1,
    this.extra = const {},
  })  : assert(rowSpan >= 1),
        assert(colSpan >= 1);

  /// A blank cell with no lines.
  static const empty = SlideTableCell();

  /// The text, one entry per paragraph.
  final List<TextParagraph> paragraphs;

  /// The cell's own fill, or `null` to take the table's (its header or band
  /// color, or none). See `TableElement.fillAt`.
  final SlideColor? fill;

  /// The lines along the cell's edges.
  final CellBorders borders;

  /// Where the text sits between the cell's top and bottom.
  final TextAnchor anchor;

  /// How many rows the cell spans down, 1 for an unmerged cell.
  final int rowSpan;

  /// How many columns the cell spans across, 1 for an unmerged cell.
  final int colSpan;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  /// Whether the cell is the anchor of a merged area.
  bool get isMerged => rowSpan > 1 || colSpan > 1;

  /// The text with styling dropped, paragraphs joined by `\n`.
  String get plainText => paragraphs.map((p) => p.plainText).join('\n');

  static const _known = {
    'paragraphs',
    'fill',
    'borders',
    'anchor',
    'rowSpan',
    'colSpan',
  };

  /// Reads a cell from its `.qslide` object at [path].
  factory SlideTableCell.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final paragraphs = optionalList(json, 'paragraphs', path);
    final fill = optionalString(json, 'fill', path);
    int span(String key) {
      final n = optionalNumber(json, key, path) ?? 1;
      if (n < 1 || n != n.truncateToDouble()) {
        throw QslideFormatException(
          'expected a positive integer',
          path: '$path.$key',
        );
      }
      return n.toInt();
    }

    return SlideTableCell(
      paragraphs: List.unmodifiable([
        for (var i = 0; i < paragraphs.length; i++)
          TextParagraph.fromJson(paragraphs[i], '$path.paragraphs[$i]'),
      ]),
      fill: fill == null ? null : SlideColor.parse(fill, path: '$path.fill'),
      borders: json['borders'] == null
          ? CellBorders.none
          : CellBorders.fromJson(json['borders'], '$path.borders'),
      anchor: enumByName(json, 'anchor', TextAnchor.values, TextAnchor.top),
      rowSpan: span('rowSpan'),
      colSpan: span('colSpan'),
      extra: unknownFields(json, _known),
    );
  }

  /// The cell as its `.qslide` object; a blank cell is `{}`.
  JsonMap toJson() => {
        ...extra,
        if (paragraphs.isNotEmpty)
          'paragraphs': [for (final p in paragraphs) p.toJson()],
        if (fill != null) 'fill': fill!.toHex(),
        if (!borders.isEmpty) 'borders': borders.toJson(),
        if (anchor != TextAnchor.top) 'anchor': anchor.name,
        if (rowSpan != 1) 'rowSpan': rowSpan,
        if (colSpan != 1) 'colSpan': colSpan,
      };

  /// Returns a copy with the given fields replaced; pass `null` as [fill]
  /// to clear it.
  SlideTableCell copyWith({
    List<TextParagraph>? paragraphs,
    Object? fill = unset,
    CellBorders? borders,
    TextAnchor? anchor,
    int? rowSpan,
    int? colSpan,
  }) =>
      SlideTableCell(
        paragraphs: paragraphs ?? this.paragraphs,
        fill: identical(fill, unset) ? this.fill : fill as SlideColor?,
        borders: borders ?? this.borders,
        anchor: anchor ?? this.anchor,
        rowSpan: rowSpan ?? this.rowSpan,
        colSpan: colSpan ?? this.colSpan,
        extra: extra,
      );

  /// The cell with rows and columns swapped, as transposing a table needs.
  SlideTableCell get transposed => copyWith(
        borders: borders.transposed,
        rowSpan: colSpan,
        colSpan: rowSpan,
      );

  @override
  bool operator ==(Object other) =>
      other is SlideTableCell &&
      other.fill == fill &&
      other.borders == borders &&
      other.anchor == anchor &&
      other.rowSpan == rowSpan &&
      other.colSpan == colSpan &&
      listEquals(other.paragraphs, paragraphs) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(paragraphs),
        fill,
        borders,
        anchor,
        rowSpan,
        colSpan,
        jsonHash(extra),
      );
}
