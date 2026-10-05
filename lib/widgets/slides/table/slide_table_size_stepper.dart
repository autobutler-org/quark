import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One of the table picker's steppers: [label], one less, the [value],
/// one more, kept between [min] and [max]. The value reads to a screen
/// reader as "Rows 3".
///
/// Key prefixes: `slide_table_<name>_less`, `slide_table_<name>_more` and
/// `slide_table_<name>_value`.
class SlideTableSizeStepper extends StatelessWidget {
  /// A stepper keyed by [name], reading [label] and [value].
  const SlideTableSizeStepper({
    required this.name,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 20,
    super.key,
  });

  /// The name its keys are built from: `rows`, `columns`.
  final String name;

  /// What it counts: "Rows", "Columns".
  final String label;

  /// The count.
  final int value;

  /// Called with the new count.
  final ValueChanged<int> onChanged;

  /// The smallest count.
  final int min;

  /// The largest count.
  final int max;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: text.bodyMedium?.copyWith(color: tokens.foreground),
          ),
        ),
        QuarkBarIconButton(
          key: ValueKey('slide_table_${name}_less'),
          icon: QuarkIcons.remove,
          tooltip: 'Fewer ${label.toLowerCase()}',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 36),
          child: Semantics(
            label: '$label $value',
            excludeSemantics: true,
            child: Text(
              '$value',
              key: ValueKey('slide_table_${name}_value'),
              textAlign: TextAlign.center,
              style: text.labelLarge?.copyWith(color: tokens.foreground),
            ),
          ),
        ),
        QuarkBarIconButton(
          key: ValueKey('slide_table_${name}_more'),
          icon: QuarkIcons.add,
          tooltip: 'More ${label.toLowerCase()}',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
