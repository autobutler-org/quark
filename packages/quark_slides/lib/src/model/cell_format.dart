import 'cell_border_preset.dart';
import 'stroke.dart';
import 'text_format.dart';
import 'unset.dart';

/// A change to a range of table cells, as
/// `SlideDocumentController.formatCells` applies it. A field left out
/// leaves that property alone.
///
/// - [text]: a [TextFormat] over each cell's whole text — bold, italic,
///   color, size, alignment — and its `anchor`, which places the text
///   between the cell's top and bottom.
/// - [fill]: a `SlideColor` for a solid fill, `null` to fall back to the
///   table's header or band color.
/// - [borders] with [borderStroke]: draws [borderStroke] (the table's
///   default line when `null`) along the edges the preset names;
///   [CellBorderPreset.none] removes every line in and around the range.
///
/// ```dart
/// const CellFormat(text: TextFormat(bold: true));
/// const CellFormat(fill: SlideColor.theme(ThemeColor.accent2));
/// const CellFormat(text: TextFormat(alignment: TextAlignment.center, anchor: TextAnchor.middle));
/// CellFormat(borders: CellBorderPreset.outside, borderStroke: Stroke(width: 4));
/// ```
class CellFormat {
  /// Creates a change; see the class doc.
  const CellFormat({
    this.text,
    this.fill = unset,
    this.borders,
    this.borderStroke,
  });

  /// The text and anchor change, or `null` to leave the text alone.
  final TextFormat? text;

  /// A `SlideColor`, `null` for the table's own fill, or [unset].
  final Object? fill;

  /// Which edges to draw or clear, or `null` to leave the lines alone.
  final CellBorderPreset? borders;

  /// The line [borders] draws; the table's default when `null`.
  final Stroke? borderStroke;
}
