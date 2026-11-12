import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// A horizontal capacity meter whose fill color escalates as it fills:
/// primary while there is room, warning past three quarters, error past nine
/// tenths.
///
/// The fill animates between values, so handing it a new [usedFraction] on a
/// refresh reads as movement rather than a jump.
///
/// Emits no `ValueKey`s; it is not interactive.
///
/// ```dart
/// QuarkStorageBar(usedFraction: used / total);
/// ```
class QuarkStorageBar extends StatelessWidget {
  /// Creates a bar filled to [usedFraction] of its width.
  const QuarkStorageBar({
    required this.usedFraction,
    this.height = 8.0,
    super.key,
  });

  /// How full the volume is, from 0 to 1. Values outside that range are
  /// clamped, so a caller does not have to guard a divide by zero.
  final double usedFraction;

  /// The bar's thickness in logical pixels.
  final double height;

  /// The fill color for [fraction], under the current theme's tokens.
  ///
  /// Exposed so a caller can color a matching label the same way.
  static Color colorForFraction(double fraction, QuarkTokens tokens) {
    if (fraction >= 0.9) return tokens.error;
    if (fraction >= 0.75) return tokens.warning;
    return tokens.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final clamped = usedFraction.clamp(0.0, 1.0);
    final color = colorForFraction(clamped, tokens);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedFractionallySizedBox(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: Alignment.centerLeft,
        widthFactor: clamped,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
        ),
      ),
    );
  }
}
