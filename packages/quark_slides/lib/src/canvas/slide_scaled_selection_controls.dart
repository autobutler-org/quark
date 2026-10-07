import 'package:flutter/widgets.dart';

/// Selection handles for a text field drawn inside a scaled slide, at the
/// size [base] draws them on screen rather than shrunk or blown up with
/// the slide.
///
/// The in-place editor lays text out in slide units and the canvas scales
/// the whole slide to fit, and handles follow their text through that
/// scale. This sizes each handle by 1/[scale] in slide units, so on screen
/// it comes out the size a touch needs.
class SlideScaledSelectionControls extends TextSelectionControls
    with TextSelectionHandleControls {
  /// Wraps [base] for a slide drawn at [scale] screen pixels per unit.
  SlideScaledSelectionControls(this.base, this.scale);

  /// The platform's own handles.
  final TextSelectionControls base;

  /// Screen pixels per slide unit.
  final double scale;

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final screenHeight = textLineHeight * scale;
    return SizedBox.fromSize(
      size: getHandleSize(textLineHeight),
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox.fromSize(
          size: base.getHandleSize(screenHeight),
          child: base.buildHandle(context, type, screenHeight, onTap),
        ),
      ),
    );
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      base.getHandleAnchor(type, textLineHeight * scale) / scale;

  @override
  Size getHandleSize(double textLineHeight) =>
      base.getHandleSize(textLineHeight * scale) / scale;
}
