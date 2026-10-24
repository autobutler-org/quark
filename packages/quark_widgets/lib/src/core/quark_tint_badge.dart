import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// A small outlined chip with one word in [color], on a light tint of the
/// same color: a beta mark, a drive's health verdict, a backup's protection
/// level.
///
/// The word is always drawn. Color repeats it and never replaces it. It is
/// decoration, not a control, so it takes no callbacks.
///
/// Key prefixes: `beta_badge` on [QuarkTintBadge.beta]. Every other badge
/// takes its key from the caller: `drive_health_badge[_<id>]` and
/// `data_protection_badge[_<id>]` in this package and the app.
///
/// ```dart
/// QuarkTintBadge(
///   key: const ValueKey('drive_health_badge'),
///   label: verdict.label,
///   color: driveHealthVerdictColor(QuarkTokens.of(context), verdict),
///   semanticLabel: '${verdict.label} drive health',
/// );
/// const QuarkTintBadge.beta();
/// ```
class QuarkTintBadge extends StatelessWidget {
  /// Creates a badge reading [label].
  const QuarkTintBadge({
    required this.label,
    this.color,
    this.semanticLabel,
    this.dense = false,
    super.key,
  });

  /// The beta mark beside a section or a feature flag, keyed `beta_badge`.
  const QuarkTintBadge.beta()
    : this(label: 'Beta', dense: true, key: const ValueKey('beta_badge'));

  /// The word on the chip.
  final String label;

  /// The text, outline and tint color. Null uses [QuarkTokens.primary].
  final Color? color;

  /// What a screen reader hears, when the word alone does not say what it
  /// is about. Null leaves the word as the label.
  final String? semanticLabel;

  /// Whether to draw the smaller chip that sits inline beside a label.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final color = this.color ?? tokens.primary;
    final semanticLabel = this.semanticLabel;

    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Padding(
        padding: dense
            ? EdgeInsets.symmetric(horizontal: tokens.spacingXs)
            : EdgeInsets.symmetric(
                horizontal: tokens.spacingSm,
                vertical: tokens.spacingXs,
              ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: dense ? 11 : 12,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
    return semanticLabel == null
        ? badge
        : Semantics(label: semanticLabel, child: badge);
  }
}
