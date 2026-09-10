import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'quark_checkerboard/checkerboard_painter.dart';

/// The alternating squares image editors paint behind artwork to say "these
/// pixels are transparent".
///
/// A transparent PNG or SVG drawn straight onto a page shows the page's own
/// background through its holes, so the artwork reads as if it were on a solid
/// canvas — and a white logo on the dark theme looks identical to an opaque
/// one. The checkerboard is the conventional answer: it is busy enough to be
/// obviously not part of the image, and neutral enough that light and dark
/// artwork both stay readable on it.
///
/// The two colors come from [QuarkTokens.card] and [QuarkTokens.border], so the
/// board follows the theme: near-white against pale gray in the light theme,
/// navy against a lighter navy in the dark one. Both pairs are one step apart
/// on the neutral ramp — enough to read as a grid, not enough to compete with
/// what sits on top.
///
/// [child] is painted over the board and decides the size, so wrap it in
/// something that fills the space (a [SizedBox.expand], a [Center], a
/// [Positioned.fill]) when the board should cover more than the child does.
///
/// Key prefixes: none. Nothing here is tappable, so there is nothing for a
/// `.probe` script to address — find it by type in a test.
///
/// ```dart
/// QuarkCheckerboard(
///   child: InteractiveViewer(
///     child: Center(child: SvgPicture.memory(bytes, fit: BoxFit.contain)),
///   ),
/// );
/// ```
class QuarkCheckerboard extends StatelessWidget {
  /// Creates a checkerboard backdrop behind [child].
  const QuarkCheckerboard({
    required this.child,
    this.squareSize = defaultSquareSize,
    super.key,
  });

  /// Drawn on top of the board, and the source of the board's size.
  final Widget child;

  /// The edge length of one square, in logical pixels.
  ///
  /// The default reads as a texture rather than a pattern at arm's length;
  /// shrink it behind a thumbnail, where 16 pixel squares would be most of the
  /// tile.
  final double squareSize;

  /// The square size used when none is given.
  static const double defaultSquareSize = 16;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return CustomPaint(
      painter: CheckerboardPainter(
        light: tokens.card,
        dark: tokens.border,
        squareSize: squareSize,
      ),
      // The child paints over the board rather than beside it, and sizes it.
      child: child,
    );
  }
}
