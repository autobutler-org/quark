import '../format/json_fields.dart';
import 'text_run.dart';

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

/// One paragraph of a text box: a list of styled [runs] and an [alignment].
///
/// An empty paragraph (no runs) is a blank line.
class TextParagraph {
  /// Creates a paragraph.
  const TextParagraph(
    this.runs, {
    this.alignment = TextAlignment.start,
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

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  /// The paragraph's characters with styling dropped.
  String get plainText => runs.map((r) => r.text).join();

  static const _known = {'runs', 'align'};

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
      extra: unknownFields(json, _known),
    );
  }

  /// The paragraph as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'runs': [for (final run in runs) run.toJson()],
        if (alignment != TextAlignment.start) 'align': alignment.name,
      };

  @override
  bool operator ==(Object other) =>
      other is TextParagraph &&
      other.alignment == alignment &&
      listEquals(other.runs, runs) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(runs), alignment, jsonHash(extra));

  @override
  String toString() => 'TextParagraph($plainText)';
}
