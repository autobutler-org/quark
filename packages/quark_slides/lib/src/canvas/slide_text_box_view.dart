import 'package:flutter/widgets.dart';

import '../model/rich_text.dart';
import '../model/slide_element.dart';
import '../model/text_paragraph.dart';
import '../theme/slide_theme.dart';
import 'slide_canvas_style.dart';
import 'slide_text_highlight_painter.dart';
import 'slide_text_layout.dart';
import 'slide_text_paragraph_view.dart';

/// Draws a [TextBox]'s paragraphs inside its frame, in slide units.
///
/// Each paragraph is one block of styled runs with its own alignment, line
/// spacing and list marker, laid out by [SlideTextLayout]; a run that
/// leaves its size, family or color unset takes them from [theme]'s style
/// for the box's [TextBox.textRole]. The text sits against the box's
/// [TextBox.anchor] edge. Text taller than the frame runs past it, as it
/// does in other slide editors, instead of being cut off — unless the box
/// shrinks text to fit ([TextAutoFit.shrink]).
///
/// With [showPlaceholder], an empty box shows its [TextBox.placeholder] in
/// [SlideCanvasStyle.placeholderColor], as an editor does and a slideshow
/// does not.
///
/// [highlights] — search matches — are painted behind their characters by
/// a [SlideTextHighlightPainter] laid out exactly as the paragraph is.
class SlideTextBoxView extends StatelessWidget {
  /// Creates the view of [box].
  const SlideTextBoxView({
    super.key,
    required this.box,
    required this.style,
    required this.theme,
    this.showPlaceholder = false,
    this.highlights = const [],
  });

  /// The text box to draw.
  final TextBox box;

  /// Supplies the placeholder color.
  final SlideCanvasStyle style;

  /// The theme the slide's role colors and unset text styles resolve
  /// against: the deck's, or `SlideThemes.light`.
  final SlideTheme theme;

  /// Whether an empty box shows its placeholder.
  final bool showPlaceholder;

  /// The characters to highlight, in [style]'s highlight colors.
  final List<SlideTextHighlight> highlights;

  /// The alignment that holds text against [anchor]'s edge.
  static Alignment alignmentOf(TextAnchor anchor) => switch (anchor) {
        TextAnchor.top => Alignment.topLeft,
        TextAnchor.middle => Alignment.centerLeft,
        TextAnchor.bottom => Alignment.bottomLeft,
      };

  @override
  Widget build(BuildContext context) {
    final layout = SlideTextLayout.forBox(box, theme);
    final scale = layout.shrinkScale(box);
    final placeholder =
        showPlaceholder && box.placeholder.isNotEmpty && box.plainText.isEmpty;
    final paragraphs = placeholder
        ? [
            TextParagraph.plain(box.placeholder).copyWith(
              alignment: box.paragraphs.firstOrNull?.alignment,
            ),
          ]
        : box.paragraphs;
    final markers = listMarkers(paragraphs);
    return OverflowBox(
      alignment: alignmentOf(box.anchor),
      minHeight: 0,
      maxHeight: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < paragraphs.length; i++)
            SlideTextParagraphView(
              paragraph: paragraphs[i],
              layout: layout,
              marker: markers[i],
              scale: scale,
              child: CustomPaint(
                painter: placeholder ? null : _painter(i, layout, scale),
                child: RichText(
                  text: placeholder
                      ? TextSpan(
                          text: box.placeholder,
                          style: layout
                              .rootStyle(box.paragraphs.firstOrNull ??
                                  paragraphs.first)
                              .copyWith(color: style.placeholderColor),
                        )
                      : layout.paragraphSpan(paragraphs[i], scale: scale),
                  textAlign: layout.textAlign(paragraphs[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The painter of paragraph [index]'s highlights, laid out as [layout]
  /// draws it at [scale]; `null` when it has none.
  SlideTextHighlightPainter? _painter(
    int index,
    SlideTextLayout layout,
    double scale,
  ) {
    final mine = [
      for (final h in highlights)
        if (h.paragraph == index) h,
    ];
    if (mine.isEmpty) return null;
    final paragraph = box.paragraphs[index];
    return SlideTextHighlightPainter(
      span: layout.paragraphSpan(paragraph, scale: scale),
      textAlign: layout.textAlign(paragraph),
      highlights: mine,
      color: style.highlightColor,
      currentColor: style.currentHighlightColor,
    );
  }
}
