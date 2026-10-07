import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/transition/slide_transition_labels.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The choice of a transition's kind: None, Fade, Push, Wipe or Zoom as
/// chips, the current one selected (#1164).
///
/// Key prefixes: `slide_transition_kind_<name>` on each chip, such as
/// `slide_transition_kind_fade`.
class SlideTransitionKindField extends StatelessWidget {
  /// The chips for [kind]; [onChanged] null leaves them unresponsive.
  const SlideTransitionKindField({
    required this.kind,
    required this.onChanged,
    super.key,
  });

  /// The kind in effect.
  final SlideTransitionKind kind;

  /// Called with the kind picked.
  final ValueChanged<SlideTransitionKind>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Wrap(
      spacing: tokens.spacingSm,
      runSpacing: tokens.spacingSm,
      children: [
        for (final value in SlideTransitionKind.values)
          ChoiceChip(
            key: ValueKey('slide_transition_kind_${value.name}'),
            label: Text(SlideTransitionLabels.kind(value)),
            selected: value == kind,
            onSelected: onChanged == null ? null : (_) => onChanged!(value),
          ),
      ],
    );
  }
}
