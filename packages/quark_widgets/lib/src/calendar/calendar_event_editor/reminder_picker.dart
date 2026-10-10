import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../calendar_labels.dart';
import '../calendar_reminders.dart';
import 'editor_picker_button.dart';
import 'reminder_choice_chip.dart';

/// The reminder choices as a row of chips, with a line beneath saying where a
/// reminder shows up.
///
/// A timed event offers Off, At start, and 5, 15, 30 and 60 minutes before.
/// An all-day event counts back from its midnight, so it offers the day itself
/// or the day before, at 9 AM until a time is picked. Once it has a reminder,
/// a time button beneath the chips reports [onPickTime], and both chips move
/// to the time chosen. A saved value that is not one of these (set elsewhere)
/// is kept as a chip of its own, so opening the editor never quietly changes
/// it.
///
/// Key prefixes: `event_remind_off`, `event_remind_<minutes>` on each
/// choice, for example `event_remind_15` and `event_remind_900`, and
/// `event_remind_time` on an all-day reminder's time button.
class ReminderPicker extends StatelessWidget {
  /// Creates the picker showing [value].
  const ReminderPicker({
    required this.value,
    required this.allDay,
    required this.onChanged,
    this.onPickTime,
    super.key,
  });

  /// Minutes before the start, or null for no reminder.
  final int? value;

  /// Whether the event is all day, which changes the choices.
  final bool allDay;

  /// Called with the choice picked; null turns the reminder off.
  final ValueChanged<int?> onChanged;

  /// Opens a picker for the time of day an all-day reminder falls at. The
  /// time button shows only for an all-day event with a reminder set.
  final VoidCallback? onPickTime;

  /// The minutes a timed event offers.
  static const List<int> timedChoices = [0, 5, 15, 30, 60];

  /// The minutes an all-day event offers at [minuteOfDay]: that time on the
  /// day, and the day before.
  static List<int> allDayChoices(int minuteOfDay) => [
    for (final daysBefore in [0, 1])
      CalendarReminders.allDayMinutes(
        daysBefore: daysBefore,
        minuteOfDay: minuteOfDay,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final current = value;
    final minuteOfDay = current == null
        ? CalendarReminders.defaultAllDayMinuteOfDay
        : CalendarReminders.allDayMinuteOfDay(current);
    final choices = allDay ? allDayChoices(minuteOfDay) : timedChoices;

    String label(int minutes) {
      if (!allDay) {
        if (minutes == 0) return 'At start';
        return minutes == 60 ? '1 hour' : '$minutes min';
      }
      return CalendarLabels.reminder(
        minutes,
        allDay: true,
        use24Hour: use24Hour,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ReminderChoiceChip(
              minutes: null,
              label: 'Off',
              selected: current == null,
              onSelected: onChanged,
            ),
            for (final minutes in [
              ...choices,
              if (current != null && !choices.contains(current)) current,
            ])
              ReminderChoiceChip(
                minutes: minutes,
                label: choices.contains(minutes)
                    ? label(minutes)
                    : CalendarLabels.reminder(
                        minutes,
                        allDay: allDay,
                        use24Hour: use24Hour,
                      ),
                selected: current == minutes,
                onSelected: onChanged,
              ),
          ],
        ),
        if (allDay && current != null)
          EditorPickerButton(
            key: const ValueKey('event_remind_time'),
            value: CalendarLabels.time(
              DateTime(2000, 1, 1, minuteOfDay ~/ 60, minuteOfDay % 60),
              use24Hour: use24Hour,
            ),
            semanticLabel: 'Reminder time',
            onPressed: onPickTime,
          ),
        Text(
          'Shows in Upcoming. Phone alerts coming later.',
          style: TextStyle(fontSize: 12, color: tokens.secondaryForeground),
        ),
      ],
    );
  }
}
