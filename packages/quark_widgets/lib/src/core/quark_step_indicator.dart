import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// Where a multi-step flow stands: a line naming the current step, over a row
/// of segments with one filled for every step reached.
///
/// Place it above the content of a step in a flow whose steps are fixed and
/// known up front, such as first-boot setup. The caller owns the position and
/// passes a new [currentIndex] as the flow moves.
///
/// It is static: nothing animates, so there is no reduced-motion variant.
///
/// Key prefixes: `step_indicator_label` on the line of text, and
/// `step_indicator_segment_<index>` on each segment. The segments are hidden
/// from screen readers, which hear only the text.
///
/// ```dart
/// QuarkStepIndicator(
///   steps: const ['Create account', 'Recovery phrase', 'Theme'],
///   currentIndex: 1,
/// );
/// ```
class QuarkStepIndicator extends StatelessWidget {
  /// Creates an indicator showing step [currentIndex] of [steps].
  const QuarkStepIndicator({
    required this.steps,
    required this.currentIndex,
    super.key,
  });

  /// The name of every step, in order. Must not be empty.
  final List<String> steps;

  /// The zero-based index of the step being shown. Must be within [steps].
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    // Checked here, not in the constructor: a list's length is not a constant
    // expression, so an assert on it there would rule out `const` call sites.
    assert(currentIndex >= 0 && currentIndex < steps.length);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = QuarkTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step ${currentIndex + 1} of ${steps.length} — ${steps[currentIndex]}',
          key: const ValueKey('step_indicator_label'),
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: tokens.spacingSm),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) SizedBox(width: tokens.spacingXs),
                Expanded(
                  child: DecoratedBox(
                    key: ValueKey('step_indicator_segment_$i'),
                    decoration: BoxDecoration(
                      color: i <= currentIndex
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(tokens.radiusSm / 2),
                    ),
                    child: const SizedBox(height: 4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
