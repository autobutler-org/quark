import '../model/element_frame.dart';
import '../model/slide_element.dart';
import '../model/slide_size.dart';
import '../model/text_paragraph.dart';
import '../theme/theme_text_role.dart';

/// One slot a `SlideLayout` defines: a text box of a [role] at a place on
/// the slide, with a [prompt] shown while it is empty.
///
/// Its geometry is in fractions of the slide — [left], [top], [width] and
/// [height] from 0 to 1 — so one layout fits 16:9 and 4:3 decks alike;
/// [frameOn] gives it in slide units. A slide's text box that fills the
/// slot carries its [id] as `TextBox.slot`.
class LayoutPlaceholder {
  /// Creates a slot; the geometry is in fractions of the slide.
  const LayoutPlaceholder({
    required this.id,
    required this.role,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.prompt = '',
    this.anchor = TextAnchor.top,
    this.alignment = TextAlignment.start,
  });

  /// The slot's id within its layout: `title`, `subtitle`, `body`, `left`,
  /// `right`.
  final String id;

  /// Which theme text style the slot's text takes.
  final ThemeTextRole role;

  /// The left edge, as a fraction of the slide's width.
  final double left;

  /// The top edge, as a fraction of the slide's height.
  final double top;

  /// The width, as a fraction of the slide's width.
  final double width;

  /// The height, as a fraction of the slide's height.
  final double height;

  /// What an editor shows while the slot is empty: "Click to add title".
  final String prompt;

  /// Where the text sits vertically in the box.
  final TextAnchor anchor;

  /// How the text's lines are aligned.
  final TextAlignment alignment;

  /// The slot's frame on a slide of [size].
  ElementFrame frameOn(SlideSize size) => ElementFrame(
        x: left * size.width,
        y: top * size.height,
        width: width * size.width,
        height: height * size.height,
      );

  /// An empty text box filling the slot on a slide of [size], with [id].
  TextBox emptyBox(String id, SlideSize size) => TextBox(
        id: id,
        frame: frameOn(size),
        paragraphs: [TextParagraph(const [], alignment: alignment)],
        anchor: anchor,
        autoFit: TextAutoFit.shrink,
        placeholder: prompt,
        slot: this.id,
        textRole: role,
      );
}
