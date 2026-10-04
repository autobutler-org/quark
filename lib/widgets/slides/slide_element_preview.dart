import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';

/// One element of a slide, drawn read-only inside its frame for
/// `SlideStage`.
///
/// Text boxes draw their styled runs, shapes their fill and outline, lines
/// a stroke corner to corner, and images a labeled placeholder until the
/// canvas loads them. An element of a type this version does not know draws
/// nothing; it is still kept in the file.
///
/// Colors here are the presentation's own, not the app theme's: a slide
/// looks the same in light and dark mode.
class SlideElementPreview extends StatelessWidget {
  /// Draws [element]; the caller sizes and places it from its frame.
  const SlideElementPreview({required this.element, super.key});

  /// The element to draw.
  final SlideElement element;

  /// The size text takes when a run sets none, in slide units.
  static const double defaultFontSize = 40;

  static Color _color(SlideColor? color, Color fallback) =>
      color == null ? fallback : Color(color.argb);

  @override
  Widget build(BuildContext context) => switch (element) {
    TextBox(:final paragraphs) => ClipRect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final paragraph in paragraphs)
            Text.rich(
              TextSpan(
                children: [
                  for (final run in paragraph.runs)
                    TextSpan(
                      text: run.text,
                      style: TextStyle(
                        fontSize: run.fontSize ?? defaultFontSize,
                        fontFamily: run.fontFamily,
                        fontWeight: run.bold ? FontWeight.bold : null,
                        fontStyle: run.italic ? FontStyle.italic : null,
                        decoration: run.underline
                            ? TextDecoration.underline
                            : null,
                        color: _color(run.color, Colors.black),
                      ),
                    ),
                ],
              ),
              textAlign: switch (paragraph.alignment) {
                TextAlignment.start => TextAlign.start,
                TextAlignment.center => TextAlign.center,
                TextAlignment.end => TextAlign.end,
                TextAlignment.justify => TextAlign.justify,
              },
            ),
        ],
      ),
    ),
    ShapeElement(:final kind, :final fill, :final stroke) => DecoratedBox(
      decoration: ShapeDecoration(
        color: fill == null ? null : Color(fill.argb),
        shape: _shape(
          kind,
          stroke == null
              ? BorderSide.none
              : BorderSide(
                  color: Color(stroke.color.argb),
                  width: stroke.width,
                ),
        ),
      ),
    ),
    LineElement(:final stroke, :final flipped) => CustomPaint(
      painter: _LinePainter(
        color: Color(stroke.color.argb),
        width: stroke.width,
        flipped: flipped,
      ),
    ),
    ImageElement(:final altText) => ColoredBox(
      color: Colors.black12,
      child: Center(
        child: Icon(
          QuarkIcons.image_outlined,
          size: 96,
          color: Colors.black38,
          semanticLabel: altText.isEmpty ? null : altText,
        ),
      ),
    ),
    GroupElement() || UnknownElement() => const SizedBox.shrink(),
  };

  static ShapeBorder _shape(ShapeKind kind, BorderSide side) => switch (kind) {
    ShapeKind.rectangle ||
    ShapeKind.arrow => RoundedRectangleBorder(side: side),
    ShapeKind.roundedRectangle => RoundedRectangleBorder(
      side: side,
      borderRadius: BorderRadius.circular(32),
    ),
    ShapeKind.ellipse => OvalBorder(side: side),
    ShapeKind.triangle => StarBorder.polygon(side: side, sides: 3),
    ShapeKind.diamond => StarBorder.polygon(side: side, sides: 4),
    ShapeKind.star => StarBorder(side: side, points: 5, innerRadiusRatio: 0.4),
  };

  /// [ElementFrame.rotation], in degrees, as radians for [Transform.rotate].
  static double radians(double degrees) => degrees * math.pi / 180;
}

/// A straight line across its box, top-left to bottom-right, or bottom-left
/// to top-right when [flipped].
class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.color,
    required this.width,
    required this.flipped,
  });

  final Color color;
  final double width;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      flipped ? Offset(0, size.height) : Offset.zero,
      flipped ? Offset(size.width, 0) : Offset(size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || old.width != width || old.flipped != flipped;
}
