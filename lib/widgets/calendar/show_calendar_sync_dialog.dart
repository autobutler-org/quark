import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/calendar_controller.dart';
import 'package:quark/widgets/calendar/calendar_sync_dialog.dart';

/// Opens [CalendarSyncDialog] over the calendar (#1151): the subscription link
/// and the .ics import, through [calendar]. It completes when the dialog
/// closes.
Future<void> showCalendarSyncDialog(
  BuildContext context, {
  required CalendarController calendar,
}) => showDialog<void>(
  context: context,
  builder: (_) => CalendarSyncDialog(calendar: calendar),
);
