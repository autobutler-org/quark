import 'slide_color.dart';
import 'slide_element.dart';
import 'text_paragraph.dart';
import 'text_run.dart';
import 'unset.dart';

/// A change to text formatting, or a summary of the formatting a selection
/// has.
///
/// **As a change** — what `formatTextBox` and the editing commands take —
/// a field left out leaves that property alone. The run fields ([bold] to
/// [color]) restyle characters, the paragraph fields ([alignment],
/// [lineSpacing], [list]) restyle every paragraph the selection touches, and
/// the box fields ([anchor], [autoFit]) restyle the whole box. Pass `null`
/// to [fontSize], [fontFamily], [color] or [lineSpacing] to make it inherit
/// again.
///
/// ```dart
/// const TextFormat(bold: true, fontSize: 48.0);
/// const TextFormat(alignment: TextAlignment.center);
/// const TextFormat(color: null); // back to the theme's text color
/// ```
///
/// **As a summary** — what `textFormatOf` returns — a field holds the value
/// every character (or paragraph) in the selection shares, and is left out
/// (`null`, or [unset] for the nullable ones) where they differ. So
/// `summary.bold == true` lights a toolbar's bold button, and
/// `summary.fontSize is double` gives its size box a number.
class TextFormat {
  /// Creates a change or a summary; see the class doc.
  const TextFormat({
    this.bold,
    this.italic,
    this.underline,
    this.strikethrough,
    this.fontSize = unset,
    this.fontFamily = unset,
    this.color = unset,
    this.alignment,
    this.lineSpacing = unset,
    this.list,
    this.anchor,
    this.autoFit,
  });

  /// Bold on or off.
  final bool? bold;

  /// Italic on or off.
  final bool? italic;

  /// Underline on or off.
  final bool? underline;

  /// Strikethrough on or off.
  final bool? strikethrough;

  /// A `double` size in slide units, `null` to inherit, or [unset].
  final Object? fontSize;

  /// A `String` family, `null` to inherit, or [unset].
  final Object? fontFamily;

  /// A [SlideColor], `null` to inherit, or [unset].
  final Object? color;

  /// Paragraph alignment.
  final TextAlignment? alignment;

  /// A `double` line spacing, `null` for the default, or [unset].
  final Object? lineSpacing;

  /// Paragraph list style.
  final TextListStyle? list;

  /// The box's vertical anchor.
  final TextAnchor? anchor;

  /// The box's fit.
  final TextAutoFit? autoFit;

  /// Whether this changes any run style.
  bool get changesRuns =>
      bold != null ||
      italic != null ||
      underline != null ||
      strikethrough != null ||
      !identical(fontSize, unset) ||
      !identical(fontFamily, unset) ||
      !identical(color, unset);

  /// Whether this changes any paragraph style.
  bool get changesParagraphs =>
      alignment != null || !identical(lineSpacing, unset) || list != null;

  /// Whether this changes the box itself.
  bool get changesBox => anchor != null || autoFit != null;

  /// [run] with this format's run fields applied.
  TextRun applyToRun(TextRun run) => run.copyWith(
        bold: bold,
        italic: italic,
        underline: underline,
        strikethrough: strikethrough,
        fontSize: fontSize,
        fontFamily: fontFamily,
        color: color,
      );

  /// [paragraph] with this format's paragraph fields applied.
  TextParagraph applyToParagraph(TextParagraph paragraph) => paragraph.copyWith(
        alignment: alignment,
        lineSpacing: lineSpacing,
        list: list,
      );

  /// [box] with this format's box fields applied; its text is untouched.
  TextBox applyToBox(TextBox box) =>
      box.copyWith(anchor: anchor, autoFit: autoFit);

  /// This format with [other]'s set fields laid over it.
  TextFormat merge(TextFormat other) {
    Object? pick(Object? mine, Object? theirs) =>
        identical(theirs, unset) ? mine : theirs;
    return TextFormat(
      bold: other.bold ?? bold,
      italic: other.italic ?? italic,
      underline: other.underline ?? underline,
      strikethrough: other.strikethrough ?? strikethrough,
      fontSize: pick(fontSize, other.fontSize),
      fontFamily: pick(fontFamily, other.fontFamily),
      color: pick(color, other.color),
      alignment: other.alignment ?? alignment,
      lineSpacing: pick(lineSpacing, other.lineSpacing),
      list: other.list ?? list,
      anchor: other.anchor ?? anchor,
      autoFit: other.autoFit ?? autoFit,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextFormat &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.color == color &&
      other.alignment == alignment &&
      other.lineSpacing == lineSpacing &&
      other.list == list &&
      other.anchor == anchor &&
      other.autoFit == autoFit;

  @override
  int get hashCode => Object.hash(
        bold,
        italic,
        underline,
        strikethrough,
        fontSize,
        fontFamily,
        color,
        alignment,
        lineSpacing,
        list,
        anchor,
        autoFit,
      );

  @override
  String toString() => 'TextFormat('
      '${[
        if (bold != null) 'bold: $bold',
        if (italic != null) 'italic: $italic',
        if (underline != null) 'underline: $underline',
        if (strikethrough != null) 'strikethrough: $strikethrough',
        if (!identical(fontSize, unset)) 'fontSize: $fontSize',
        if (!identical(fontFamily, unset)) 'fontFamily: $fontFamily',
        if (!identical(color, unset)) 'color: $color',
        if (alignment != null) 'alignment: ${alignment!.name}',
        if (!identical(lineSpacing, unset)) 'lineSpacing: $lineSpacing',
        if (list != null) 'list: ${list!.name}',
        if (anchor != null) 'anchor: ${anchor!.name}',
        if (autoFit != null) 'autoFit: ${autoFit!.name}',
      ].join(', ')})';
}

/// The on/off formatting commands a toolbar button or a shortcut flips.
enum TextToggle {
  /// Bold, Ctrl or Cmd B.
  bold,

  /// Italic, Ctrl or Cmd I.
  italic,

  /// Underline, Ctrl or Cmd U.
  underline,

  /// Strikethrough.
  strikethrough,

  /// A bulleted list.
  bulletList,

  /// A numbered list.
  numberedList;

  /// The change that flips this toggle for a selection whose formatting is
  /// [current] (a summary from `textFormatOf`): on unless every character
  /// or paragraph already has it, as other editors do with a mixed
  /// selection.
  TextFormat changeFrom(TextFormat current) => switch (this) {
        bold => TextFormat(bold: current.bold != true),
        italic => TextFormat(italic: current.italic != true),
        underline => TextFormat(underline: current.underline != true),
        strikethrough =>
          TextFormat(strikethrough: current.strikethrough != true),
        bulletList => TextFormat(
            list: current.list == TextListStyle.bullet
                ? TextListStyle.none
                : TextListStyle.bullet,
          ),
        numberedList => TextFormat(
            list: current.list == TextListStyle.numbered
                ? TextListStyle.none
                : TextListStyle.numbered,
          ),
      };

  /// Whether a selection formatted as [current] has this toggle on.
  bool isOn(TextFormat current) => switch (this) {
        bold => current.bold == true,
        italic => current.italic == true,
        underline => current.underline == true,
        strikethrough => current.strikethrough == true,
        bulletList => current.list == TextListStyle.bullet,
        numberedList => current.list == TextListStyle.numbered,
      };
}
