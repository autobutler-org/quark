/// Which way a directional transition moves: the direction the slides
/// travel, so [left] brings the new slide in from the right edge.
///
/// It names the same directions as PresentationML's `dir` attribute
/// (`l`, `r`, `u`, `d`). An unknown direction in a `.qslide` file reads as
/// [left].
enum SlideTransitionDirection {
  /// Toward the left edge; the new slide enters from the right.
  left,

  /// Toward the right edge; the new slide enters from the left.
  right,

  /// Toward the top edge; the new slide enters from the bottom.
  up,

  /// Toward the bottom edge; the new slide enters from the top.
  down;

  /// The opposite direction, which stepping back through a show plays.
  SlideTransitionDirection get reversed => switch (this) {
        left => right,
        right => left,
        up => down,
        down => up,
      };
}
