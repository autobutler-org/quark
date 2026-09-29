import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// A small outlined chip that marks a feature as beta, drawn in the accent
/// color from the theme tokens.
///
/// Reusable for anything labeled beta: a drawer row, a page title, a settings
/// section. It is decoration, not a control, so it takes no callbacks.
///
/// Key prefixes: `beta_badge` on the chip.
///
/// ```dart
/// Row(
///   children: [
///     const Text('Chat'),
///     const SizedBox(width: 8),
///     const QuarkBetaBadge(),
///   ],
/// );
/// ```
class QuarkBetaBadge extends StatelessWidget {
  /// Creates a badge reading [label].
  const QuarkBetaBadge({this.label = 'Beta', super.key});

  /// The word on the chip.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return DecoratedBox(
      key: const ValueKey('beta_badge'),
      decoration: BoxDecoration(
        color: tokens.primary.withValues(alpha: 0.12),
        border: Border.all(color: tokens.primary),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacingXs),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: tokens.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
