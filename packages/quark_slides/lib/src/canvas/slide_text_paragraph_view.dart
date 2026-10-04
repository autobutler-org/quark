import 'package:flutter/widgets.dart';

import '../model/text_paragraph.dart';
import 'slide_text_layout.dart';

/// One paragraph of a text box: its list [marker], when it has one, right
/// aligned a little short of a gutter [SlideTextLayout.markerWidth] wide,
/// and then [child] — the paragraph's text, drawn or being edited — filling
/// the rest of the width.
///
/// The text view and the in-place editor both build their paragraphs with
/// this, so a paragraph wraps the same way whether or not it is being
/// edited.
class SlideTextParagraphView extends StatelessWidget {
  /// Creates the row for [paragraph].
  const SlideTextParagraphView({
    super.key,
    required this.paragraph,
    required this.layout,
    required this.child,
    this.marker,
    this.scale = 1,
  });

  /// The paragraph, for its marker's style and gutter width.
  final TextParagraph paragraph;

  /// Styles the marker.
  final SlideTextLayout layout;

  /// The paragraph's text.
  final Widget child;

  /// The list marker (`•`, `3.`), or `null` for a plain paragraph.
  final String? marker;

  /// The shrink-to-fit scale the box is drawn at.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final marker = this.marker;
    if (marker == null) return child;
    final gutter = layout.markerWidth(paragraph, scale: scale);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: gutter,
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: gutter / 4),
            child: RichText(
              text: TextSpan(
                text: marker,
                style: layout.rootStyle(paragraph, scale: scale),
              ),
              textAlign: TextAlign.end,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
