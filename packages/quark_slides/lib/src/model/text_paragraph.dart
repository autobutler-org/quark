import '../format/json_fields.dart';
import 'text_run.dart';
import 'unset.dart';

/// How a paragraph's lines sit between the text box's edges.
enum TextAlignment {
  /// Flush with the leading edge (left, in left-to-right text).
  start,

  /// Centered.
  center,

  /// Flush with the trailing edge.
  end,

  /// Stretched to both edges, except the last line.
  justify,
}

/// Whether a paragraph is a list item, and how its marker reads.
enum TextListStyle {
  /// An ordinary paragraph.
  none,

  /// A bulleted list item.
  bullet,

  /// A numbered list item, counted from the first of an unbroken run of
  /// numbered paragraphs.
  numbered,
}

/// One paragraph of a text box: a list of styled [runs], an [alignment], a
/// [lineSpacing] and a [list] style.
///
/// An empty paragraph (no text) is a blank line. It may keep one empty run,
/// whose style is what typing into the line starts with.
class TextParagraph {
  /// Creates a paragraph.
  const TextParagraph(
    this.runs, {
    this.alignment = TextAlignment.start,
    this.lineSpacing,
    this.list = TextListStyle.none,
    this.extra = const {},
  });

  /// A paragraph of one unstyled run, or a blank line when [text] is empty.
  factory TextParagraph.plain(
    String text, {
    TextAlignment alignment = TextAlignment.start,
  }) =>
      TextParagraph(
        text.isEmpty ? const [] : [TextRun(text)],
        alignment: alignment,
      );

  /// The styled spans, in reading order.
  final List<TextRun> runs;

  /// Horizontal alignment of the paragraph's lines.
  final TextAlignment alignment;

  /// Line height as a multiple of the font size, or `null` for the
  /// default, [defaultLineSpacing].
  final double? lineSpacing;

  /// Whether the paragraph is a list item.
  final TextListStyle list;

  /// The line height of a paragraph that leaves [lineSpacing] unset.
  static const defaultLineSpacing = 1.2;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  /// The paragraph's characters with styling dropped.
  String get plainText => runs.map((r) => r.text).join();

  static const _known = {'runs', 'align', 'lineSpacing', 'list'};

  /// Reads a paragraph from its `.qslide` object at [path]. An alignment
  /// this version does not know reads as [TextAlignment.start].
  factory TextParagraph.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final runs = optionalList(json, 'runs', path);
    return TextParagraph(
      List.unmodifiable([
        for (var i = 0; i < runs.length; i++)
          TextRun.fromJson(runs[i], '$path.runs[$i]'),
      ]),
      alignment: enumByName(
        json,
        'align',
        TextAlignment.values,
        TextAlignment.start,
      ),
      lineSpacing: optionalNumber(json, 'lineSpacing', path),
      list: enumByName(json, 'list', TextListStyle.values, TextListStyle.none),
      extra: unknownFields(json, _known),
    );
  }

  /// The paragraph as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'runs': [for (final run in runs) run.toJson()],
        if (alignment != TextAlignment.start) 'align': alignment.name,
        if (lineSpacing != null) 'lineSpacing': jsonNumber(lineSpacing!),
        if (list != TextListStyle.none) 'list': list.name,
      };

  /// Returns a copy with the given fields replaced; pass `null` as
  /// [lineSpacing] to restore the default.
  TextParagraph copyWith({
    List<TextRun>? runs,
    TextAlignment? alignment,
    Object? lineSpacing = unset,
    TextListStyle? list,
  }) =>
      TextParagraph(
        runs ?? this.runs,
        alignment: alignment ?? this.alignment,
        lineSpacing: identical(lineSpacing, unset)
            ? this.lineSpacing
            : lineSpacing as double?,
        list: list ?? this.list,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is TextParagraph &&
      other.alignment == alignment &&
      other.lineSpacing == lineSpacing &&
      other.list == list &&
      listEquals(other.runs, runs) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(runs),
        alignment,
        lineSpacing,
        list,
        jsonHash(extra),
      );

  @override
  String toString() => 'TextParagraph($plainText)';
}
