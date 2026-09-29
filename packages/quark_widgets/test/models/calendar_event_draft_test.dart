import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The edits the event form makes, each keeping the draft coherent.
void main() {
  final vet = CalendarEventDraft(
    title: 'Vet',
    start: DateTime(2026, 9, 29, 16),
    end: DateTime(2026, 9, 29, 16, 45),
    reminderMinutes: 30,
  );

  test('a new timed draft is an hour long', () {
    final draft = CalendarEventDraft.at(DateTime(2026, 9, 17, 16));
    expect(draft.end, DateTime(2026, 9, 17, 17));
    expect(draft.allDay, isFalse);
  });

  test('a new all-day draft covers its one date', () {
    final draft = CalendarEventDraft.allDayOn(DateTime(2026, 9, 17, 13, 20));
    expect(draft.start, DateTime(2026, 9, 17));
    expect(draft.end, DateTime(2026, 9, 18));
    expect(draft.lastDate, DateTime(2026, 9, 17));
  });

  test('moving the start date keeps the time and the length', () {
    final moved = vet.withStartDate(DateTime(2026, 10, 2));
    expect(moved.start, DateTime(2026, 10, 2, 16));
    expect(moved.end, DateTime(2026, 10, 2, 16, 45));
  });

  test('moving an all-day start keeps its number of dates', () {
    final weekend = CalendarEventDraft(
      start: DateTime(2026, 9, 26),
      end: DateTime(2026, 9, 28),
      allDay: true,
    );
    final moved = weekend.withStartDate(DateTime(2026, 10, 10));
    expect(moved.start, DateTime(2026, 10, 10));
    expect(moved.end, DateTime(2026, 10, 12));
  });

  test('moving the start time keeps the length', () {
    final moved = vet.withStartTime(9, 30);
    expect(moved.start, DateTime(2026, 9, 29, 9, 30));
    expect(moved.end, DateTime(2026, 9, 29, 10, 15));
  });

  test('the end date of an all-day draft is its last, inclusive date', () {
    final draft = CalendarEventDraft.allDayOn(DateTime(2026, 9, 26));
    final longer = draft.withEndDate(DateTime(2026, 9, 27));
    expect(longer.end, DateTime(2026, 9, 28));
    expect(longer.lastDate, DateTime(2026, 9, 27));
  });

  test('an end before the start is kept for the form to flag', () {
    final backwards = vet.withEndTime(15, 0);
    expect(backwards.end, DateTime(2026, 9, 29, 15));
    expect(backwards.endsAfterStart, isFalse);
  });

  test('switching all day on covers the dates and clears the reminder', () {
    final allDay = vet.withAllDay(true);
    expect(allDay.allDay, isTrue);
    expect(allDay.start, DateTime(2026, 9, 29));
    expect(allDay.end, DateTime(2026, 9, 30));
    expect(allDay.reminderMinutes, isNull);
  });

  test('switching all day off gives 9 to 10 on its first date', () {
    final timed = CalendarEventDraft.allDayOn(
      DateTime(2026, 9, 26),
    ).withAllDay(false);
    expect(timed.start, DateTime(2026, 9, 26, 9));
    expect(timed.end, DateTime(2026, 9, 26, 10));
    expect(vet.withAllDay(false), vet);
  });

  test('copyWith keeps a reminder unless told to clear it', () {
    expect(vet.copyWith(title: 'Vet visit').reminderMinutes, 30);
    expect(vet.copyWith(clearReminder: true).reminderMinutes, isNull);
    expect(vet.copyWith(reminderMinutes: 5).reminderMinutes, 5);
  });
}
