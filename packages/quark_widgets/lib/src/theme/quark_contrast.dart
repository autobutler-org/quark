import 'dart:math' as math;
import 'dart:ui' show Color;

/// The WCAG contrast ratio between [a] and [b], from 1.0 to 21.0.
///
/// Text needs 4.5 against what it sits on, and a boundary such as a focus
/// ring needs 3.0. Theme color derivation and its contrast tests both
/// measure with this, so the two cannot disagree about what passes.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Whichever of [a] and [b] contrasts more with [background], for text and
/// icons drawn on a fill whose color is not known until runtime.
Color moreLegibleOn(Color background, Color a, Color b) =>
    contrastRatio(a, background) >= contrastRatio(b, background) ? a : b;
