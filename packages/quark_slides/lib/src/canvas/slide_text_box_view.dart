import 'package:flutter/widgets.dart';

import '../model/slide_element.dart';
import '../model/text_paragraph.dart';
import '../model/text_run.dart';
import 'slide_canvas_style.dart';

/// Draws a [TextBox]'s paragraphs inside its frame, in slide units.
///
/// Each paragraph is one block of styled runs with its own alignment. A run
/// that leaves its size or color unset takes [SlideCanvasStyle.fontSize] or
/// [SlideCanvasStyle.textColor]. Text taller than the frame runs past its
/// bottom, as it does in other slide editors, instead of being cut off.
class SlideTextBoxView extends StatelessWidget {
  /// Creates the view of [box].
  const SlideTextBoxView({super.key, required this.box, required this.style});

  /// The text box to draw.
  final TextBox box;

  /// Supplies the defaults for unset run styles.
  final SlideCanvasStyle style;

  static const _alignments = {
    TextAlignment.start: TextAlign.start,
    TextAlignment.center: TextAlign.center,
    TextAlignment.end: TextAlign.end,
    TextAlignment.justify: TextAlign.justify,
  };

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: style.fontSize,
      color: style.textColor,
      height: 1.2,
    );
    return OverflowBox(
      alignment: Alignment.topLeft,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final paragraph in box.paragraphs)
            Text.rich(
              TextSpan(
                style: base,
                children: [for (final run in paragraph.runs) _span(run)],
              ),
              textAlign: _alignments[paragraph.alignment],
            ),
        ],
      ),
    );
  }

  static TextSpan _span(TextRun run) => TextSpan(
        text: run.text,
        style: TextStyle(
          fontSize: run.fontSize,
          fontFamily: run.fontFamily,
          color: run.color == null ? null : Color(run.color!.argb),
          fontWeight: run.bold ? FontWeight.bold : null,
          fontStyle: run.italic ? FontStyle.italic : null,
          decoration: run.underline ? TextDecoration.underline : null,
        ),
      );
}
