package calendarutil

import (
	"context"
	"slices"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// reminderSlack is how far an all-day reminder, which keeps its time of day,
// can sit from one counted back from midnight in minutes: a daylight saving
// change, an hour nearly everywhere.
const reminderSlack = 3 * time.Hour

// Occurrence is one occurrence of an event, in the event's time zone.
type Occurrence struct {
	// Start and End are instants. An all-day occurrence runs from midnight
	// on its first date to midnight after its last, in the event's zone.
	Start time.Time
	End   time.Time
	// ReminderAt is when its reminder falls, or nil without one.
	ReminderAt *time.Time
}

// ExpandEventParams expands Event into the occurrences starting in [From, To).
type ExpandEventParams struct {
	Event Event
	From  time.Time
	To    time.Time
}

// ExpandEventResult carries the occurrences, by start.
type ExpandEventResult struct {
	Occurrences []Occurrence
}

// ExpandEvent turns a stored event into its occurrences starting in
// [From, To), following the app's rules (lib/utils/calendar_recurrence.dart)
// in the event's time zone rather than a viewer's. Every occurrence keeps the
// first one's local time of day, so 9 AM stays 9 AM on both sides of a
// daylight saving change. Weekly keeps the weekday, monthly keeps the day of
// the month and skips months without it, and a series stops after its
// RepeatUntil date on the zone's calendar. A one-off event is its own only
// occurrence.
//
// A timed reminder is ReminderMinutes before the start. An all-day one counts
// back from midnight on the clock, so 9 AM on the day is 9 AM on a 23-hour
// day too. An event with no zone, which iOS and Android still send, or one
// the zone database does not know is expanded in UTC.
func ExpandEvent(params ExpandEventParams) (ExpandEventResult, error) {
	if err := checkRange(params.From, params.To); err != nil {
		return ExpandEventResult{}, err
	}
	return ExpandEventResult{Occurrences: occurrences(params.Event, params.From, params.To)}, nil
}

// Reminder is one occurrence's reminder: Occurrence.ReminderAt is set.
type Reminder struct {
	Event      Event
	Occurrence Occurrence
}

// ListRemindersParams lists the reminders falling due in [From, To).
type ListRemindersParams struct {
	Queries *db.Queries
	From    time.Time
	To      time.Time
}

// ListRemindersResult carries the reminders, by when they fall due.
type ListRemindersResult struct {
	Reminders []Reminder
}

// ListReminders lists every reminder on the default calendar that falls due
// in [From, To), expanding repeating events as ExpandEvent does. It does not
// know which were already sent: the caller asks for each span of time once.
func ListReminders(ctx context.Context, params ListRemindersParams) (ListRemindersResult, error) {
	if err := checkRange(params.From, params.To); err != nil {
		return ListRemindersResult{}, err
	}
	// An event can start a week after its reminder, or most of a day before
	// an all-day one's; the second day covers a date read in its own zone.
	const day = 24 * time.Hour
	events, err := listEvents(ctx, params.Queries,
		params.From.Add(-2*day), params.To.Add(MaxReminderMinutes*time.Minute+2*day))
	if err != nil {
		return ListRemindersResult{}, err
	}
	reminders := []Reminder{}
	for _, event := range events {
		if event.ReminderMinutes == nil {
			continue
		}
		lead := time.Duration(*event.ReminderMinutes) * time.Minute
		for _, o := range occurrences(event, params.From.Add(lead-reminderSlack), params.To.Add(lead+reminderSlack)) {
			if !o.ReminderAt.Before(params.From) && o.ReminderAt.Before(params.To) {
				reminders = append(reminders, Reminder{Event: event, Occurrence: o})
			}
		}
	}
	slices.SortStableFunc(reminders, func(a, b Reminder) int {
		return a.Occurrence.ReminderAt.Compare(*b.Occurrence.ReminderAt)
	})
	return ListRemindersResult{Reminders: reminders}, nil
}

// occurrences is ExpandEvent without the range rules.
func occurrences(e Event, from, to time.Time) []Occurrence {
	zone := eventZone(e.TimeZone)
	first := e.Start.In(zone)
	if e.AllDay {
		// Its stored date is midnight UTC; the day begins at the zone's.
		first = time.Date(e.Start.Year(), e.Start.Month(), e.Start.Day(), 0, 0, 0, 0, zone)
	}
	length := e.End.Sub(e.Start)

	var result []Occurrence
	for k := firstStep(e.Repeat, first, from.In(zone)); ; k++ {
		start, exists := occurrenceStart(e.Repeat, first, k)
		year, month, day := start.Date()
		if !start.Before(to) ||
			(e.RepeatUntil != nil && time.Date(year, month, day, 0, 0, 0, 0, time.UTC).After(*e.RepeatUntil)) {
			break
		}
		if exists && !start.Before(from) {
			end := start.Add(length)
			if e.AllDay {
				// The same number of dates, whatever their length in hours.
				end = start.AddDate(0, 0, int(length/(24*time.Hour)))
			}
			result = append(result, Occurrence{Start: start, End: end, ReminderAt: reminderAt(e, start)})
		}
		if e.Repeat == RepeatNone {
			break
		}
	}
	return result
}

// eventZone is the zone an event's occurrences are stepped in: its own, or
// UTC when it has none or the zone database does not know it. "Local" would
// be the server's zone, which says nothing about the event.
func eventZone(name string) *time.Location {
	if zone, err := time.LoadLocation(name); err == nil && name != "Local" {
		return zone
	}
	return time.UTC
}

// firstStep is a step of the series beginning at first that starts before
// from, close enough that the range is reached without walking the series.
func firstStep(repeat Repeat, first, from time.Time) int {
	switch repeat {
	case RepeatDaily, RepeatWeekly:
		// A day short: a step on the clock can run hours past its length.
		step, _ := repeatInterval(repeat)
		return int(max(from.Sub(first)-24*time.Hour, 0) / step)
	case RepeatMonthly:
		return max(monthsBetween(first, from)-1, 0)
	default:
		return 0
	}
}

// occurrenceStart is the start of the occurrence k steps after first, at
// first's time of day in its zone, and whether that occurrence exists: a
// month without first's day has none, and its start is rolled into the next.
func occurrenceStart(repeat Repeat, first time.Time, k int) (time.Time, bool) {
	year, month, day := first.Date()
	switch repeat {
	case RepeatDaily:
		day += k
	case RepeatWeekly:
		day += 7 * k
	case RepeatMonthly:
		month += time.Month(k)
	}
	start := time.Date(year, month, day, first.Hour(), first.Minute(), first.Second(), 0, first.Location())
	return start, start.Day() == first.Day() || repeat != RepeatMonthly
}

// reminderAt is when the reminder of e's occurrence at start falls, or nil
// without one.
func reminderAt(e Event, start time.Time) *time.Time {
	if e.ReminderMinutes == nil {
		return nil
	}
	at := start.Add(-time.Duration(*e.ReminderMinutes) * time.Minute)
	if e.AllDay {
		year, month, day := start.Date()
		at = time.Date(year, month, day, 0, -*e.ReminderMinutes, 0, 0, start.Location())
	}
	return &at
}
