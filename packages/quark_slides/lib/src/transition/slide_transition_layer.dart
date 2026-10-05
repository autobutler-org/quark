import 'dart:ui';

/// Where one of the two slides in a transition is drawn at one moment: its
/// [opacity], its [offset] and the part of it [clip] shows, both as
/// fractions of the slide's box, and its [scale] about its center.
///
/// `SlideTransitionFrame.at` computes a pair of them; `SlideTransitionView`
/// paints them.
class SlideTransitionLayer {
  /// Creates a layer; the defaults draw the slide whole and in place.
  const SlideTransitionLayer({
    this.opacity = 1,
    this.offset = Offset.zero,
    this.scale = 1,
    this.clip,
  });

  /// The slide drawn whole and in place.
  static const still = SlideTransitionLayer();

  /// From 0, invisible, to 1, opaque.
  final double opacity;

  /// How far the slide is moved, in fractions of its width and height:
  /// `Offset(-1, 0)` is one whole slide to the left.
  final Offset offset;

  /// The slide's size relative to its box, about its center.
  final double scale;

  /// The part of the slide that shows, in fractions of its box —
  /// `Rect.fromLTRB(0.5, 0, 1, 1)` is its right half — or `null` for all
  /// of it.
  final Rect? clip;

  @override
  bool operator ==(Object other) =>
      other is SlideTransitionLayer &&
      other.opacity == opacity &&
      other.offset == offset &&
      other.scale == scale &&
      other.clip == clip;

  @override
  int get hashCode => Object.hash(opacity, offset, scale, clip);

  @override
  String toString() =>
      'SlideTransitionLayer(opacity: $opacity, offset: $offset, '
      'scale: $scale, clip: $clip)';
}
