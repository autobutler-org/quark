import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/transition/slide_transition_labels.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The choice of the way the slides travel in a push or wipe: Left, Right,
/// Up or Down as chips (#1164).
///
/// Key prefixes: `slide_transition_direction_<name>` on each chip.
class SlideTransitionDirectionField extends StatelessWidget {
  /// The chips for [direction]; [onChanged] null leaves them unresponsive.
  const SlideTransitionDirectionField({
    required this.direction,
    required this.onChanged,
    super.key,
  });

  /// The direction in effect.
  final SlideTransitionDirection direction;

  /// Called with the direction picked.
  final ValueChanged<SlideTransitionDirection>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Wrap(
      spacing: tokens.spacingSm,
      runSpacing: tokens.spacingSm,
      children: [
        for (final value in SlideTransitionDirection.values)
          ChoiceChip(
            key: ValueKey('slide_transition_direction_${value.name}'),
            label: Text(SlideTransitionLabels.direction(value)),
            selected: value == direction,
            onSelected: onChanged == null ? null : (_) => onChanged!(value),
          ),
      ],
    );
  }
}
