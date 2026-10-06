import 'package:flutter/widgets.dart';

import '../../theme/quark_tokens.dart';

/// Keeps interactive chrome pinned to the bottom of the screen clear of the
/// system insets and of a rounded display corner (#2788).
///
/// It clears the bottom, left, and right system insets — the home
/// indicator, a landscape notch — the way a [SafeArea] does, and never lets
/// any of those three edges come closer than the [QuarkTokens.spacingSm]
/// gutter. The gutter is for the corner curve, which `MediaQuery` never
/// reports: on an iPhone in portrait the home indicator inset leaves the
/// bottom of a bar inside the curve, and only a horizontal gutter moves its
/// corners back onto the panel. The top edge is left alone, for the app bar.
///
/// Under the keyboard it insets once. `MediaQuery.padding` drops the home
/// indicator while the keyboard covers it, and the `Scaffold` has already
/// lifted the body above the keyboard, so the child sits a gutter above it.
///
/// Use it around chrome the body pins to the bottom edge whose own box has
/// to stay whole, such as a chat composer's rounded input. A full-bleed bar
/// with a surface of its own, like the scaffold's bottom bar, wants its
/// background to reach the edge and insets only its content, and scrolling
/// content is better left to run under the edges.
///
/// The wrapper has nothing tappable, so it has no key prefixes.
///
/// ```dart
/// Column(
///   children: [
///     Expanded(child: messages),
///     QuarkEdgeInset(child: composer),
///   ],
/// );
/// ```
class QuarkEdgeInset extends StatelessWidget {
  /// Insets [child] from the bottom, left, and right screen edges.
  const QuarkEdgeInset({required this.child, super.key});

  /// The chrome to keep clear of the edges.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gutter = QuarkTokens.of(context).spacingSm;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter),
      child: child,
    );
  }
}
