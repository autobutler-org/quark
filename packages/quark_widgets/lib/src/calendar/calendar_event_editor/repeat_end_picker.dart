import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../calendar_labels.dart';
import 'editor_picker_button.dart';

/// When a repeating event in `CalendarEventEditor` stops: Never or On a date
/// as one segmented control, and on a date, a field showing it that opens the
/// date picker (#2524).
///
/// Key prefixes: `event_repeat_ends_never` and `event_repeat_ends_on` on the
/// segments, `event_repeat_until` on the date.
class RepeatEndPicker extends StatelessWidget {
  /// Creates the picker showing [value].
  const RepeatEndPicker({
    required this.value,
    required this.onEndsChanged,
    required this.onPickDate,
    this.wide = true,
    this.error,
    super.key,
  });

  /// The last date the event repeats on, or null for never.
  final DateTime? value;

  /// Called with true by On a date and false by Never.
  final ValueChanged<bool> onEndsChanged;

  /// Opens the date picker for [value].
  final VoidCallback onPickDate;

  /// Whether the date is spelled out with its weekday and year, as a wide
  /// form has room for.
  final bool wide;

  /// The caller's sentence about the date, or null. Draws the date's error
  /// border too.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final until = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text(
                'Never',
                key: ValueKey('event_repeat_ends_never'),
                maxLines: 1,
              ),
            ),
            ButtonSegment(
              value: true,
              label: Text(
                'On a date',
                key: ValueKey('event_repeat_ends_on'),
                maxLines: 1,
              ),
            ),
          ],
          selected: {until != null},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onEndsChanged(selection.single),
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
            // Standard density keeps the 48dp touch target (#2605).
            visualDensity: VisualDensity.standard,
          ),
        ),
        if (until != null)
          EditorPickerButton(
            key: const ValueKey('event_repeat_until'),
            value: wide
                ? CalendarLabels.date(until)
                : CalendarLabels.dayTitleShort(until),
            semanticLabel: 'Last repeat',
            invalid: error != null,
            onPressed: onPickDate,
          ),
        if (error != null)
          Text(error!, style: TextStyle(fontSize: 12, color: tokens.error)),
      ],
    );
  }
}
