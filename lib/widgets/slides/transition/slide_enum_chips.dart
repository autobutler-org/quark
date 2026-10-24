import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A choice among [values] as chips, [selected] selected (#1164): the
/// transition picker's kind (None, Fade, Push, Wipe, Zoom) and the way a
/// push or wipe travels (Left, Right, Up, Down).
///
/// Key prefixes: `<keyPrefix>_<name>` on each chip, such as
/// `slide_transition_kind_fade` and `slide_transition_direction_left`.
///
/// ```dart
/// SlideEnumChips(
///   values: SlideTransitionKind.values,
///   selected: kind,
///   label: SlideTransitionLabels.kind,
///   keyPrefix: 'slide_transition_kind',
///   onChanged: setKind,
/// )
/// ```
class SlideEnumChips<T extends Enum> extends StatelessWidget {
  /// The chips for [values]; [onChanged] null leaves them unresponsive.
  const SlideEnumChips({
    required this.values,
    required this.selected,
    required this.label,
    required this.keyPrefix,
    required this.onChanged,
    super.key,
  });

  /// Every choice, in order.
  final List<T> values;

  /// The choice in effect.
  final T selected;

  /// A choice's name on its chip.
  final String Function(T value) label;

  /// The start of each chip's key.
  final String keyPrefix;

  /// Called with the choice picked.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onChanged = this.onChanged;
    return Wrap(
      spacing: tokens.spacingSm,
      runSpacing: tokens.spacingSm,
      children: [
        for (final value in values)
          ChoiceChip(
            key: ValueKey('${keyPrefix}_${value.name}'),
            label: Text(label(value)),
            selected: value == selected,
            onSelected: onChanged == null ? null : (_) => onChanged(value),
          ),
      ],
    );
  }
}
