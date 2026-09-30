import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// Draws a two-pixel [QuarkTokens.primary] outline around [child] while
/// anything inside it holds keyboard focus.
///
/// Material's own focus cue for an [InkWell] is a tint painted on the
/// [Material] underneath, so a tappable whose child fills itself with a color
/// or a photo hides its own focus highlight: the tint is drawn and then
/// covered. The ring is painted in front of [child] instead, so a keyboard
/// user always sees where they are (WCAG 2.4.7).
///
/// The ring does not take focus itself. Wrap the focusable thing — an
/// [InkWell], a [Focus] — and give the ring the same [borderRadius] or
/// [shape] as the thing it outlines.
///
/// Key prefixes: none of its own. The focusable child carries the key.
///
/// ```dart
/// QuarkFocusRing(
///   borderRadius: BorderRadius.circular(tokens.radiusMd),
///   child: InkWell(key: const ValueKey('card'), onTap: open, child: card),
/// );
/// ```
class QuarkFocusRing extends StatelessWidget {
  /// Creates a ring around [child].
  const QuarkFocusRing({
    required this.child,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    super.key,
  });

  /// The focusable content the ring outlines.
  final Widget child;

  /// The corners of the ring, matching [child]'s. Ignored for a
  /// [BoxShape.circle].
  final BorderRadius? borderRadius;

  /// The ring's shape: a rectangle, or a circle for a round [child].
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          // The same DecoratedBox either way, only its border changes, so
          // the child keeps its element — and its focus — as the ring comes
          // and goes.
          return DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: focused
                  ? Border.all(color: tokens.primary, width: 2)
                  : null,
              borderRadius: shape == BoxShape.circle ? null : borderRadius,
              shape: shape,
            ),
            child: child,
          );
        },
      ),
    );
  }
}
