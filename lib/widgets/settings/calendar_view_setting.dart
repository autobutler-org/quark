import 'package:flutter/material.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/widgets/calendar/calendar_bar_bottom.dart';

/// The Settings control choosing the view Calendar opens on (#2521): a
/// heading over a dropdown of Day, Week, Month and Upcoming, in the order the
/// calendar's own view switch lists them.
///
/// The caller owns the value; this renders it and reports the pick.
///
/// Key: `settings_calendar_view` on the dropdown.
///
/// ```dart
/// CalendarViewSetting(
///   value: settings.defaultCalendarView.value,
///   onChanged: settings.setDefaultCalendarView,
/// )
/// ```
class CalendarViewSetting extends StatelessWidget {
  /// Creates the control showing [value].
  const CalendarViewSetting({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The view Calendar opens on now.
  final CalendarView value;

  /// Called with the view the user picked.
  final ValueChanged<CalendarView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Calendar opens on',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<CalendarView>(
          key: const ValueKey('settings_calendar_view'),
          initialValue: value,
          // Full width and as tall as its text, so the choice still fits at
          // large text sizes (#2606).
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            for (final view in CalendarBarBottom.order)
              DropdownMenuItem(
                value: view,
                child: Text(CalendarBarBottom.label(view)),
              ),
          ],
          onChanged: (view) {
            if (view != null) onChanged(view);
          },
        ),
      ],
    );
  }
}
