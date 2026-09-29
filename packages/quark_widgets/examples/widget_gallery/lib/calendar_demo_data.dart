import 'package:quark_widgets/quark_widgets.dart';

/// The date the calendar entries treat as today: a Tuesday late in a busy
/// month, so every surface has something to show.
final DateTime galleryToday = DateTime(2026, 9, 29);

/// The time the calendar entries treat as now, mid-afternoon on
/// [galleryToday], twenty minutes before the vet.
final DateTime galleryNow = DateTime(2026, 9, 29, 15, 40);

CalendarEventItem _timed(
  int id,
  String title,
  DateTime start,
  int minutes, {
  int color = 0,
  String location = '',
  CalendarRepeat repeat = CalendarRepeat.none,
  int? reminder,
}) => CalendarEventItem(
  eventId: id,
  title: title,
  start: start,
  end: start.add(Duration(minutes: minutes)),
  colorIndex: color,
  location: location,
  repeat: repeat,
  reminderMinutes: reminder,
);

CalendarEventItem _allDay(
  int id,
  String title,
  DateTime day, {
  int days = 1,
  int color = 0,
  CalendarRepeat repeat = CalendarRepeat.none,
  int? reminder,
}) => CalendarEventItem(
  eventId: id,
  title: title,
  start: day,
  end: CalendarDates.addDays(day, days),
  allDay: true,
  colorIndex: color,
  repeat: repeat,
  reminderMinutes: reminder,
);

/// A household's September, already expanded into occurrences the way the
/// app hands them to the widgets.
final List<CalendarEventItem> galleryEvents = [
  _allDay(
    1,
    'Rent due',
    DateTime(2026, 9, 1),
    color: 2,
    repeat: CalendarRepeat.monthly,
    reminder: 900,
  ),
  _allDay(
    1,
    'Rent due',
    DateTime(2026, 10, 1),
    color: 2,
    repeat: CalendarRepeat.monthly,
    reminder: 900,
  ),
  _allDay(2, 'Garage sale', DateTime(2026, 9, 5), color: 3),
  _allDay(3, 'Cabin weekend', DateTime(2026, 9, 26), days: 2, color: 4),
  _allDay(4, 'Garden waste pickup', DateTime(2026, 9, 29), color: 5),
  _allDay(5, 'Pay water bill', DateTime(2026, 9, 30), color: 2, reminder: -540),
  for (final day in [31, 7, 14, 21, 28])
    _timed(
      6,
      'Trash night',
      DateTime(2026, day == 31 ? 8 : 9, day, 19),
      15,
      color: 5,
      repeat: CalendarRepeat.weekly,
      reminder: 0,
    ),
  for (final day in [3, 10, 17, 24])
    _timed(
      7,
      'Soccer practice',
      DateTime(2026, 9, day, 17, 30),
      90,
      color: 1,
      location: 'Riverside Park',
      repeat: CalendarRepeat.weekly,
    ),
  _timed(8, 'Farmers market', DateTime(2026, 9, 12, 10), 120, color: 1),
  _timed(9, 'Book club', DateTime(2026, 9, 18, 19), 90, color: 3),
  _timed(10, 'Dentist', DateTime(2026, 9, 22, 9, 30), 60),
  _timed(
    11,
    'Plumber visit',
    DateTime(2026, 9, 29, 9),
    60,
    location: 'Kitchen',
  ),
  _timed(12, 'Insurance call', DateTime(2026, 9, 29, 12), 45, color: 5),
  _timed(
    13,
    'Lunch with Sam',
    DateTime(2026, 9, 29, 12, 30),
    60,
    color: 1,
    location: 'Harbor Café',
  ),
  _timed(
    14,
    'Vet — Biscuit',
    DateTime(2026, 9, 29, 16),
    45,
    color: 2,
    location: 'Riverside Vet Clinic',
    reminder: 30,
  ),
  _timed(
    15,
    'Parent–teacher night',
    DateTime(2026, 9, 29, 19),
    90,
    location: 'Lincoln Elementary',
    reminder: 60,
  ),
  _timed(16, 'Birthday party', DateTime(2026, 10, 3, 11), 180, color: 4),
];
