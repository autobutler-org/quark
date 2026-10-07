import 'package:quark_slides/quark_slides.dart';

/// The sample slides the theme and layout pickers draw their previews
/// from (#1163): a layout's empty placeholders, and a filled title and
/// content slide with a row of accent squares that shows off a theme's
/// fonts and colors.
///
/// Both are plain values with fixed ids, so building them in `build` costs
/// nothing a rebuild notices.
abstract final class SlidePreviews {
  /// [layout] as a new slide built on it would look: an empty placeholder,
  /// reading its prompt, per slot.
  static Slide forLayout(SlideLayout layout, SlideSize size) {
    var next = 0;
    return Slide(
      id: 'preview_${layout.id}',
      layoutId: layout.id,
      elements: layoutBoxes(
        layout,
        size,
        () => 'preview_${layout.id}_${next++}',
      ),
    );
  }

  /// A title and content slide with words in it and four accent squares,
  /// for drawing in each theme.
  static Slide themeSample(SlideSize size) {
    final base = forLayout(SlideLayout.titleAndContent, size);
    final boxes = base.elements.whereType<TextBox>().toList();
    final side = size.height * 0.12;
    return base.copyWith(
      elements: [
        boxes.first.copyWith(paragraphs: [TextParagraph.plain('Aa Title')]),
        boxes.last.copyWith(
          paragraphs: [
            TextParagraph.plain('Body text in the theme'),
            TextParagraph.plain('with its fonts and colors'),
          ],
        ),
        for (final (i, role) in [
          ThemeColor.accent1,
          ThemeColor.accent2,
          ThemeColor.accent3,
          ThemeColor.accent4,
        ].indexed)
          ShapeElement(
            id: 'preview_accent_$i',
            frame: ElementFrame(
              x: size.width * 0.06 + i * side * 1.25,
              y: size.height * 0.92 - side,
              width: side,
              height: side,
            ),
            fill: SlideColor.theme(role),
          ),
      ],
    );
  }
}
