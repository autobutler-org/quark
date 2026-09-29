import 'package:flutter/material.dart';

import '../../models/calendar_repeat.dart';
import '../../theme/quark_tokens.dart';
import '../calendar_labels.dart';

/// The four repeat presets as one segmented control, with the choice spelled
/// out beneath it ("Every week on Thursday").
///
/// Key prefixes: `event_repeat_<preset>` on each segment, for example
/// `event_repeat_weekly`.
class RepeatPresetPicker extends StatelessWidget {
  /// Creates the picker showing [value].
  const RepeatPresetPicker({
    required this.value,
    required this.start,
    required this.onChanged,
    this.editsSeries = false,
    super.key,
  });

  /// The chosen preset.
  final CalendarRepeat value;

  /// The first occurrence, which names the weekday or date a preset keeps.
  final DateTime start;

  /// Called with the preset picked.
  final ValueChanged<CalendarRepeat> onChanged;

  /// Whether this edits a saved repeating event, whose changes reach every
  /// occurrence. Says so beneath the control.
  final bool editsSeries;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final help = [
      if (value != CalendarRepeat.none)
        '${CalendarLabels.repeat(value, start)}.',
      if (editsSeries && value != CalendarRepeat.none)
        'Changes apply to every repeat.',
    ].join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        SegmentedButton<CalendarRepeat>(
          segments: [
            for (final preset in CalendarRepeat.values)
              ButtonSegment(
                value: preset,
                label: Text(
                  CalendarLabels.repeatShort(preset),
                  key: ValueKey('event_repeat_${preset.name}'),
                  maxLines: 1,
                ),
              ),
          ],
          selected: {value},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.single),
          style: SegmentedButton.styleFrom(
            foregroundColor: tokens.secondaryForeground,
            backgroundColor: tokens.input,
            selectedForegroundColor: tokens.primary,
            selectedBackgroundColor: tokens.primary.withValues(alpha: 0.12),
            side: BorderSide(color: tokens.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusLg),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: const VisualDensity(vertical: -1),
          ),
        ),
        if (help.isNotEmpty)
          Text(
            help,
            style: TextStyle(fontSize: 12, color: tokens.secondaryForeground),
          ),
      ],
    );
  }
}
