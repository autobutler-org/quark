import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// One choice in `ReminderPicker`: a chip tinted with the accent when chosen.
///
/// Key prefixes: `event_remind_<minutes>`, or `event_remind_off` for no
/// reminder.
class ReminderChoiceChip extends StatelessWidget {
  /// Creates the chip for [minutes] labeled [label].
  const ReminderChoiceChip({
    required this.minutes,
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The choice: minutes before the start, or null for no reminder.
  final int? minutes;

  /// The chip's words.
  final String label;

  /// Whether this is the current choice.
  final bool selected;

  /// Called with [minutes] when the chip is picked.
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return ChoiceChip(
      key: ValueKey('event_remind_${minutes ?? 'off'}'),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(minutes),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: selected ? tokens.primary : tokens.secondaryForeground,
      ),
      backgroundColor: tokens.input,
      selectedColor: tokens.primary.withValues(alpha: 0.12),
      side: BorderSide(
        color: selected ? tokens.primary.withValues(alpha: 0.4) : tokens.border,
      ),
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
    );
  }
}
