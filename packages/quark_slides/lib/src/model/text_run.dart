import '../format/json_fields.dart';
import 'slide_color.dart';
import 'unset.dart';

/// A span of text sharing one style, the unit of rich text in a text box.
///
/// A style field left `null` inherits from the theme: [fontSize] and
/// [fontFamily] from its body text, [color] from its text color.
class TextRun {
  /// Creates a run.
  const TextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.fontSize,
    this.fontFamily,
    this.color,
    this.extra = const {},
  });

  /// The characters in this run. It never contains a line break: those
  /// separate paragraphs.
  final String text;

  /// Whether the run is bold.
  final bool bold;

  /// Whether the run is italic.
  final bool italic;

  /// Whether the run is underlined.
  final bool underline;

  /// Whether the run is struck through.
  final bool strikethrough;

  /// Font size in slide units, or `null` to inherit.
  final double? fontSize;

  /// Font family name, or `null` to inherit.
  final String? fontFamily;

  /// Text color, or `null` to inherit.
  final SlideColor? color;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {
    'text',
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'fontSize',
    'fontFamily',
    'color',
  };

  /// Reads a run from its `.qslide` object at [path].
  factory TextRun.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final color = optionalString(json, 'color', path);
    return TextRun(
      requireString(json, 'text', path),
      bold: optionalBool(json, 'bold', path, false),
      italic: optionalBool(json, 'italic', path, false),
      underline: optionalBool(json, 'underline', path, false),
      strikethrough: optionalBool(json, 'strikethrough', path, false),
      fontSize: optionalNumber(json, 'fontSize', path),
      fontFamily: optionalString(json, 'fontFamily', path),
      color:
          color == null ? null : SlideColor.parse(color, path: '$path.color'),
      extra: unknownFields(json, _known),
    );
  }

  /// The run as its `.qslide` object; default styles are omitted.
  JsonMap toJson() => {
        ...extra,
        'text': text,
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (underline) 'underline': true,
        if (strikethrough) 'strikethrough': true,
        if (fontSize != null) 'fontSize': jsonNumber(fontSize!),
        if (fontFamily != null) 'fontFamily': fontFamily,
        if (color != null) 'color': color!.toHex(),
      };

  /// Returns a copy with the given fields replaced; pass `null` to a
  /// nullable style to make it inherit again.
  TextRun copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    Object? fontSize = unset,
    Object? fontFamily = unset,
    Object? color = unset,
  }) =>
      TextRun(
        text ?? this.text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        fontSize:
            identical(fontSize, unset) ? this.fontSize : fontSize as double?,
        fontFamily: identical(fontFamily, unset)
            ? this.fontFamily
            : fontFamily as String?,
        color: identical(color, unset) ? this.color : color as SlideColor?,
        extra: extra,
      );

  /// Whether [other] is styled exactly like this run — every field but
  /// [text] matches, unknown fields included — so the two could be one run.
  bool hasStyleOf(TextRun other) => other.copyWith(text: text) == this;

  @override
  bool operator ==(Object other) =>
      other is TextRun &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.color == color &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        text,
        bold,
        italic,
        underline,
        strikethrough,
        fontSize,
        fontFamily,
        color,
        jsonHash(extra),
      );

  @override
  String toString() => 'TextRun($text)';
}
