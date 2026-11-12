import 'package:material_ui/material_ui.dart';

/// When a file version was saved, as the version history shows it: the date
/// with its year and the time of day, in the device's time zone and the
/// locale's order, such as `Oct 11, 2026, 3:04 PM`.
String formatVersionTime(BuildContext context, DateTime savedAt) {
  final localizations = MaterialLocalizations.of(context);
  final local = savedAt.toLocal();
  return '${localizations.formatShortMonthDay(local)}, ${local.year}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
