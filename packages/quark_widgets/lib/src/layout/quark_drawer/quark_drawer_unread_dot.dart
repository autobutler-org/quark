import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// The dot on a `QuarkDrawer` row that says something there is unread: a
/// small filled circle in the chrome's primary color.
///
/// It reads as [label] to a screen reader, so the signal is not color alone.
/// A part of `QuarkDrawer`, which keys it, and tested through it.
class QuarkDrawerUnreadDot extends StatelessWidget {
  /// Creates the dot.
  const QuarkDrawerUnreadDot({super.key});

  /// What the dot says aloud.
  static const String label = 'Unread messages';

  /// The dot's diameter.
  static const double size = 8;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context).onChrome;

    return Semantics(
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.primary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
