import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/rich_text.dart';
import '../model/slide_element.dart';
import '../model/text_paragraph.dart';
import '../model/text_run.dart';
import '../theme/slide_theme.dart';
import '../theme/slide_themes.dart';
import 'slide_canvas_style.dart';

/// How a [TextBox]'s text is styled and laid out, in slide units, shared by
/// the canvas's text view, its in-place editor and the auto-grow measurer
/// so that all three wrap every line at the same place.
///
/// A paragraph is one block: its runs as [TextSpan]s under a root style
/// that carries the default size and color, its line spacing as the
/// style's `height`, and — for a list item — a marker in a gutter
/// [markerWidth] wide before it. A box with [TextAutoFit.shrink] draws every
/// size multiplied by [shrinkScale].
///
/// ```dart
/// final layout = SlideTextLayout.fromStyle(style);
/// final height = layout.contentHeight(box); // what auto-grow fits to
/// ```
///
/// A box drawn in a theme uses [SlideTextLayout.forBox]: its unset runs
/// take the theme's text style for the box's `ThemeTextRole`, and theme
/// role colors resolve against [theme].
///
/// Its [measure] is the [TextBoxMeasurer] `SlideDocumentNotifier` gives its
/// controller by default.
class SlideTextLayout {
  /// Creates a layout whose unstyled runs are [fontSize], [textColor] and
  /// [fontFamily], and whose role colors resolve against [theme].
  const SlideTextLayout({
    this.fontSize = 36,
    this.textColor = const Color(0xFF000000),
    this.fontFamily,
    this.theme,
  });

  /// A layout with [style]'s text defaults.
  factory SlideTextLayout.fromStyle(SlideCanvasStyle style) =>
      SlideTextLayout(fontSize: style.fontSize, textColor: style.textColor);

  /// The layout of [box] in [theme]: unset runs take the size, family and
  /// color of the theme's style for the box's `TextBox.textRole`.
  factory SlideTextLayout.forBox(TextBox box, SlideTheme theme) {
    final style = theme.textStyle(box.textRole);
    return SlideTextLayout(
      fontSize: style.fontSize,
      textColor: Color(style.color.resolve(theme)),
      fontFamily: theme.fontOf(style),
      theme: theme,
    );
  }

  /// The size of a run that leaves its own unset, in slide units.
  final double fontSize;

  /// The color of a run that leaves its own unset.
  final Color textColor;

  /// The family of a run that leaves its own unset, or `null` for the
  /// platform's default.
  final String? fontFamily;

  /// The theme a run's role color resolves against, or `null` for each
  /// role's fallback.
  final SlideTheme? theme;

  /// The smallest [shrinkScale]: text is never drawn below a quarter size.
  static const minShrinkScale = 0.25;

  static const _alignments = {
    TextAlignment.start: TextAlign.start,
    TextAlignment.center: TextAlign.center,
    TextAlignment.end: TextAlign.end,
    TextAlignment.justify: TextAlign.justify,
  };

  /// The Flutter alignment of [paragraph].
  TextAlign textAlign(TextParagraph paragraph) =>
      _alignments[paragraph.alignment]!;

  /// The style of [run] relative to its paragraph's [rootStyle], with every
  /// size multiplied by [scale].
  TextStyle runStyle(TextRun run, {double scale = 1}) => TextStyle(
        fontSize: run.fontSize == null ? null : run.fontSize! * scale,
        fontFamily: run.fontFamily,
        color: run.color == null ? null : Color(run.color!.resolve(theme)),
        fontWeight: run.bold ? FontWeight.bold : null,
        fontStyle: run.italic ? FontStyle.italic : null,
        decoration: TextDecoration.combine([
          if (run.underline) TextDecoration.underline,
          if (run.strikethrough) TextDecoration.lineThrough,
        ]),
      );

  /// The style every run of [paragraph] inherits: the defaults, the
  /// paragraph's line spacing, and its first run's own style, so an empty
  /// line and the list marker are as tall as the text that starts it.
  ///
  /// It does not inherit from the ambient `DefaultTextStyle`: a slide looks
  /// the same in every app.
  TextStyle rootStyle(TextParagraph paragraph, {double scale = 1}) {
    final base = TextStyle(
      inherit: false,
      fontSize: fontSize * scale,
      fontFamily: fontFamily,
      color: textColor,
      height: paragraph.lineSpacing ?? TextParagraph.defaultLineSpacing,
    );
    return paragraph.runs.isEmpty
        ? base
        : base.merge(runStyle(paragraph.runs.first, scale: scale));
  }

  /// [paragraph]'s text as a span tree under its [rootStyle].
  TextSpan paragraphSpan(TextParagraph paragraph, {double scale = 1}) =>
      TextSpan(
        style: rootStyle(paragraph, scale: scale),
        children: [
          for (final run in paragraph.runs)
            if (run.text.isNotEmpty)
              TextSpan(text: run.text, style: runStyle(run, scale: scale)),
        ],
      );

  /// The width of the gutter a list item's marker sits in: one and a half
  /// times its first line's font size.
  double markerWidth(TextParagraph paragraph, {double scale = 1}) =>
      (rootStyle(paragraph, scale: scale).fontSize ?? fontSize) * 1.5;

  /// How tall [box]'s text lays out at its frame's width, with sizes
  /// multiplied by [scale].
  double contentHeight(TextBox box, {double scale = 1}) {
    final markers = listMarkers(box.paragraphs);
    var height = 0.0;
    for (var i = 0; i < box.paragraphs.length; i++) {
      final paragraph = box.paragraphs[i];
      final gutter =
          markers[i] == null ? 0.0 : markerWidth(paragraph, scale: scale);
      final text = _paint(
        paragraphSpan(paragraph, scale: scale),
        textAlign(paragraph),
        math.max(0, box.frame.width - gutter),
      );
      var line = text.height;
      text.dispose();
      if (markers[i] != null) {
        final marker = _paint(
          TextSpan(text: markers[i], style: rootStyle(paragraph, scale: scale)),
          TextAlign.end,
          gutter,
        );
        line = math.max(line, marker.height);
        marker.dispose();
      }
      height += line;
    }
    return height;
  }

  /// The height [box]'s text needs at its frame's width in [theme]; a
  /// [TextBoxMeasurer] for `SlideDocumentController.measureText`.
  ///
  /// With no theme, the box is measured as a canvas draws a deck with none:
  /// the light theme's type, with body text at [fontSize].
  double measure(TextBox box, [SlideTheme? theme]) => SlideTextLayout.forBox(
        box,
        theme ??
            SlideThemes.light.copyWith(
              body: SlideThemes.light.body.copyWith(fontSize: fontSize),
            ),
      ).contentHeight(box);

  /// The scale at which [box]'s text fits its frame's height: 1 when it
  /// already fits or the box does not shrink text, and never below
  /// [minShrinkScale].
  double shrinkScale(TextBox box) {
    if (box.autoFit != TextAutoFit.shrink ||
        contentHeight(box) <= box.frame.height) {
      return 1;
    }
    var low = minShrinkScale;
    var high = 1.0;
    for (var i = 0; i < 10; i++) {
      final mid = (low + high) / 2;
      if (contentHeight(box, scale: mid) <= box.frame.height) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  static TextPainter _paint(TextSpan span, TextAlign align, double width) =>
      TextPainter(
        text: span,
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
}
