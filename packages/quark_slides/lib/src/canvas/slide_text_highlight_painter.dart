import 'package:flutter/widgets.dart';

/// One span of a text box to highlight: the characters from [start] to
/// [end] of its [paragraph]'s plain text, emphasized when [current].
typedef SlideTextHighlight = ({
  int paragraph,
  int start,
  int end,
  bool current,
});

/// Paints search highlights behind one paragraph of a text box.
///
/// It lays out [span] — the same span, alignment and width the paragraph's
/// `RichText` is drawn with — and fills the boxes `TextPainter` gives for
/// each highlight's characters, so a rectangle sits exactly behind its text
/// on every line it wraps across. The [current] highlight is filled in
/// [currentColor] and outlined in it too; the rest in [color].
class SlideTextHighlightPainter extends CustomPainter {
  /// Creates a painter of [highlights] over [span].
  SlideTextHighlightPainter({
    required this.span,
    required this.textAlign,
    required this.highlights,
    required this.color,
    required this.currentColor,
  });

  /// The paragraph's text, as drawn.
  final InlineSpan span;

  /// The paragraph's alignment.
  final TextAlign textAlign;

  /// What to highlight.
  final List<SlideTextHighlight> highlights;

  /// The fill of an ordinary highlight.
  final Color color;

  /// The fill and outline of the current one.
  final Color currentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: size.width, maxWidth: size.width);
    final fill = Paint();
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = currentColor;
    for (final h in highlights) {
      fill.color = h.current ? currentColor : color;
      for (final box in text.getBoxesForSelection(
        TextSelection(baseOffset: h.start, extentOffset: h.end),
      )) {
        final rect = box.toRect();
        canvas.drawRect(rect, fill);
        if (h.current) canvas.drawRect(rect.inflate(1), outline);
      }
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(SlideTextHighlightPainter old) =>
      old.span != span ||
      old.textAlign != textAlign ||
      old.color != color ||
      old.currentColor != currentColor ||
      !_same(old.highlights, highlights);

  static bool _same(List<SlideTextHighlight> a, List<SlideTextHighlight> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
