import 'package:flutter/material.dart';

/// The colors and sizes a `SlideCanvas` draws its chrome with: the
/// selection, handles, guides, letterbox and search highlights. A slide's
/// own content is colored by its deck's theme, never by this.
///
/// The package does not know the host app's design tokens, so this is the
/// value class an app feeds them through. Leave it out and
/// [SlideCanvasStyle.fromTheme] derives one from the ambient [ColorScheme].
///
/// ```dart
/// SlideCanvas(
///   document: doc,
///   slideId: slideId,
///   style: SlideCanvasStyle.fromTheme(Theme.of(context)).copyWith(
///     selectionColor: tokens.accent,
///   ),
/// );
/// ```
class SlideCanvasStyle {
  /// Creates a style.
  const SlideCanvasStyle({
    required this.selectionColor,
    required this.handleFillColor,
    required this.guideColor,
    required this.backdropColor,
    required this.placeholderColor,
    this.handleSize = 12,
    this.handleHitSize = 48,
    this.rotateHandleOffset = 32,
    this.snapDistance = 8,
    this.highlightColor = const Color(0x66FFC107),
    this.currentHighlightColor = const Color(0xCCFF9800),
  });

  /// A style in the colors of [theme]'s [ColorScheme]: the primary color
  /// for the selection, the tertiary for snap guides, and the lowest surface
  /// container behind the slide.
  factory SlideCanvasStyle.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return SlideCanvasStyle(
      selectionColor: scheme.primary,
      handleFillColor: scheme.surface,
      guideColor: scheme.tertiary,
      backdropColor: scheme.surfaceContainerLowest,
      placeholderColor: scheme.outline,
    );
  }

  /// The selection outline, handle borders and marquee.
  final Color selectionColor;

  /// The inside of a handle.
  final Color handleFillColor;

  /// The snap guide lines.
  final Color guideColor;

  /// The letterbox around the slide.
  final Color backdropColor;

  /// The outline of an element the canvas cannot draw: an image with no
  /// image builder, or an element type this version does not know.
  final Color placeholderColor;

  /// The drawn size of a handle, in logical pixels.
  final double handleSize;

  /// The size of the area around a handle that grabs it, in logical
  /// pixels: 48 by default, a comfortable touch target.
  final double handleHitSize;

  /// How far above the top edge the rotate handle sits, in logical pixels.
  final double rotateHandleOffset;

  /// How close, in logical pixels, a dragged edge or center has to come to
  /// a guide to snap to it.
  final double snapDistance;

  /// The fill behind text a search found: translucent amber by default,
  /// readable over light and dark slides alike.
  final Color highlightColor;

  /// The fill and outline of the match a search is on: a stronger orange
  /// by default.
  final Color currentHighlightColor;

  /// Returns a copy with the given fields replaced.
  SlideCanvasStyle copyWith({
    Color? selectionColor,
    Color? handleFillColor,
    Color? guideColor,
    Color? backdropColor,
    Color? placeholderColor,
    double? handleSize,
    double? handleHitSize,
    double? rotateHandleOffset,
    double? snapDistance,
    Color? highlightColor,
    Color? currentHighlightColor,
  }) =>
      SlideCanvasStyle(
        selectionColor: selectionColor ?? this.selectionColor,
        handleFillColor: handleFillColor ?? this.handleFillColor,
        guideColor: guideColor ?? this.guideColor,
        backdropColor: backdropColor ?? this.backdropColor,
        placeholderColor: placeholderColor ?? this.placeholderColor,
        handleSize: handleSize ?? this.handleSize,
        handleHitSize: handleHitSize ?? this.handleHitSize,
        rotateHandleOffset: rotateHandleOffset ?? this.rotateHandleOffset,
        snapDistance: snapDistance ?? this.snapDistance,
        highlightColor: highlightColor ?? this.highlightColor,
        currentHighlightColor:
            currentHighlightColor ?? this.currentHighlightColor,
      );
}
