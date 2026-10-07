import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

import '../model/slide_size.dart';

/// Maps between a slide's units and the pixels of the box it is shown in.
///
/// At [zoom] 1 the slide is scaled to fit inside [viewportSize] less
/// [padding], keeping its aspect ratio and centered, with letterbox bars on
/// the two sides it does not fill. Other zooms multiply that fitted scale,
/// so 0.5 shows the slide at half its fitted size and 2 at double. When the
/// zoomed slide is larger than the viewport, [pan] moves it; the pan is
/// clamped so an edge of the slide never comes further in than the
/// viewport's padding, and is zero on an axis the slide fits.
class SlideViewport {
  /// Creates a viewport; [pan] is clamped as the class describes.
  SlideViewport({
    required this.viewportSize,
    required this.slideSize,
    this.zoom = 1,
    Offset pan = Offset.zero,
    this.padding = EdgeInsets.zero,
  }) {
    final available = padding.deflateSize(viewportSize);
    fitScale = math.max(
      0,
      math.min(
        available.width / slideSize.width,
        available.height / slideSize.height,
      ),
    );
    final slack = Offset(
      math.max(0, scaledSlideSize.width - available.width) / 2,
      math.max(0, scaledSlideSize.height - available.height) / 2,
    );
    this.pan = Offset(
      pan.dx.clamp(-slack.dx, slack.dx),
      pan.dy.clamp(-slack.dy, slack.dy),
    );
    origin = padding.topLeft +
        Offset(
          (available.width - scaledSlideSize.width) / 2,
          (available.height - scaledSlideSize.height) / 2,
        ) +
        this.pan;
  }

  /// The size of the box the slide is shown in, in logical pixels.
  final Size viewportSize;

  /// The slide's size in slide units.
  final SlideSize slideSize;

  /// The zoom, relative to fitting the viewport.
  final double zoom;

  /// Space kept clear around the slide at zoom 1, in logical pixels.
  final EdgeInsets padding;

  /// The pan after clamping, in logical pixels.
  late final Offset pan;

  /// The scale at which the slide fits the padded viewport.
  late final double fitScale;

  /// Where the slide's top-left corner lands in the viewport.
  late final Offset origin;

  /// Logical pixels per slide unit.
  double get scale => fitScale * zoom;

  /// The slide's size on screen.
  Size get scaledSlideSize =>
      Size(slideSize.width * scale, slideSize.height * scale);

  /// The slide's rectangle in the viewport.
  Rect get slideRect => origin & scaledSlideSize;

  /// Converts a viewport point to slide units.
  Offset toSlide(Offset viewPoint) =>
      scale == 0 ? Offset.zero : (viewPoint - origin) / scale;

  /// Converts a point in slide units to the viewport.
  Offset toView(Offset slidePoint) => origin + slidePoint * scale;

  /// The pan that keeps the slide point under [focal] (a viewport point)
  /// where it is when the zoom changes to [newZoom], as zooming around the
  /// pointer needs. The result is not clamped; a viewport built with it
  /// clamps it.
  Offset panForZoom(double newZoom, Offset focal) =>
      panToPlace(toSlide(focal), focal, newZoom);

  /// The pan that puts [slidePoint] at the viewport point [viewPoint] at
  /// [zoom], as a pinch that pans and zooms at once needs. Not clamped.
  Offset panToPlace(Offset slidePoint, Offset viewPoint, double zoom) {
    final newScale = fitScale * zoom;
    final available = padding.deflateSize(viewportSize);
    final centered = padding.topLeft +
        Offset(
          (available.width - slideSize.width * newScale) / 2,
          (available.height - slideSize.height * newScale) / 2,
        );
    return viewPoint - slidePoint * newScale - centered;
  }
}
