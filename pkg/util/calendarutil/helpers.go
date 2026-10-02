package calendarutil

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/autobutler-org/quark/internal/db"
)

// storedTimeLayout is how a time is written to calendar_events: UTC, to the
// second, so text comparison in SQL orders it the same as time does.
const storedTimeLayout = "2006-01-02T15:04:05Z"

// invalid wraps ErrInvalidEvent with the rule that failed.
func invalid(rule string) error {
	return fmt.Errorf("%w: %s", ErrInvalidEvent, rule)
}

// validate checks input against the event rules and returns it normalized: the
// title trimmed, the times in UTC, and an empty repeat made RepeatNone.
func validate(input EventInput) (EventInput, error) {
	input.Title = strings.TrimSpace(input.Title)
	input.Start = input.Start.UTC()
	input.End = input.End.UTC()
	if input.Repeat == "" {
		input.Repeat = RepeatNone
	}

	switch {
	case input.Title == "":
		return input, invalid("a title is required")
	case utf8.RuneCountInString(input.Title) > MaxTitleLength:
		return input, invalid(fmt.Sprintf("the title can be at most %d characters", MaxTitleLength))
	case utf8.RuneCountInString(input.Location) > MaxLocationLength:
		return input, invalid(fmt.Sprintf("the location can be at most %d characters", MaxLocationLength))
	case utf8.RuneCountInString(input.Notes) > MaxNotesLength:
		return input, invalid(fmt.Sprintf("the notes can be at most %d characters", MaxNotesLength))
	case len(input.TimeZone) > MaxTimeZoneLength:
		return input, invalid("the time zone name is too long")
	case input.Start.IsZero() || input.End.IsZero():
		return input, invalid("a start and an end are required")
	case !input.End.After(input.Start):
		return input, invalid("the event must end after it starts")
	case input.ColorIndex < 0 || input.ColorIndex >= ColorCount:
		return input, invalid(fmt.Sprintf("the color must be between 0 and %d", ColorCount-1))
	}

	if input.AllDay && (!isMidnight(input.Start) || !isMidnight(input.End)) {
		return input, invalid("an all-day event starts and ends at midnight")
	}

	interval, ok := repeatInterval(input.Repeat)
	if !ok {
		return input, invalid("repeat must be none, daily, weekly or monthly")
	}
	if interval > 0 && input.End.Sub(input.Start) > interval {
		return input, invalid("a repeating event must end before it repeats")
	}

	if m := input.ReminderMinutes; m != nil {
		lowest := 0
		if input.AllDay {
			lowest = MinAllDayReminderMinutes
		}
		if *m < lowest || *m > MaxReminderMinutes {
			return input, invalid("the reminder is out of range")
		}
	}
	return input, nil
}

// isMidnight reports whether t, in UTC, falls exactly on a date boundary.
func isMidnight(t time.Time) bool {
	return t.Equal(t.Truncate(24 * time.Hour))
}

// repeatInterval is the shortest gap between two occurrences of a preset, which
// an occurrence may not outlast: zero for RepeatNone, and false for a preset
// that does not exist. A month is taken at its shortest, 28 days.
func repeatInterval(repeat Repeat) (time.Duration, bool) {
	switch repeat {
	case RepeatNone:
		return 0, true
	case RepeatDaily:
		return 24 * time.Hour, true
	case RepeatWeekly:
		return 7 * 24 * time.Hour, true
	case RepeatMonthly:
		return 28 * 24 * time.Hour, true
	default:
		return 0, false
	}
}

// occursIn reports whether an occurrence of e overlaps [from, to). The
// occurrences are stepped in UTC, where the app steps them in local time: a
// daylight saving change moves one by an hour or two, which the caller's
// day of padding absorbs. A one-off event is its own only occurrence.
func occursIn(e Event, from, to time.Time) bool {
	length := e.End.Sub(e.Start)
	overlaps := func(start time.Time) bool {
		return start.Before(to) && start.Add(length).After(from)
	}
	switch e.Repeat {
	case RepeatDaily, RepeatWeekly:
		step, _ := repeatInterval(e.Repeat)
		// Skip whole steps that end before from; an occurrence is never
		// longer than its step, so the next two decide it.
		k := time.Duration(0)
		if behind := from.Sub(e.Start) - length; behind > 0 {
			k = behind / step
		}
		start := e.Start.Add(k * step)
		return overlaps(start) || overlaps(start.Add(step))
	case RepeatMonthly:
		// Start a month before from's: an occurrence is shorter than a month,
		// so none earlier reaches it.
		for k := max(monthsBetween(e.Start, from)-1, 0); ; k++ {
			start := monthlyOccurrence(e.Start, k)
			if !start.Before(to) {
				return false
			}
			if overlaps(start) {
				return true
			}
		}
	default:
		return overlaps(e.Start)
	}
}

// monthsBetween counts the calendar months from a's to b's, in UTC.
func monthsBetween(a, b time.Time) int {
	return (b.Year()-a.Year())*12 + int(b.Month()) - int(a.Month())
}

// monthlyOccurrence is the start of the occurrence k months after first. A
// month without first's day takes its last day instead of being skipped as
// the app skips it: the app counts days in local time, where the UTC 31st may
// be the 1st, so the UTC month's end stands in for an occurrence that may
// exist there.
func monthlyOccurrence(first time.Time, k int) time.Time {
	month := time.Date(first.Year(), first.Month()+time.Month(k), 1,
		first.Hour(), first.Minute(), first.Second(), 0, time.UTC)
	day := min(first.Day(), month.AddDate(0, 1, -1).Day())
	return month.AddDate(0, 0, day-1)
}

// formatTime writes t as calendar_events stores it.
func formatTime(t time.Time) string {
	return t.UTC().Format(storedTimeLayout)
}

// boolInt is SQLite's 0 or 1 for b.
func boolInt(b bool) int64 {
	if b {
		return 1
	}
	return 0
}

// nullMinutes is the column value for an optional reminder.
func nullMinutes(m *int) sql.NullInt64 {
	if m == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: int64(*m), Valid: true}
}

// createParams maps a validated input onto the insert for calendarID.
func createParams(calendarID int64, input EventInput) db.CreateCalendarEventParams {
	return db.CreateCalendarEventParams{
		CalendarID:      calendarID,
		Title:           input.Title,
		Notes:           input.Notes,
		Location:        input.Location,
		StartsAt:        formatTime(input.Start),
		EndsAt:          formatTime(input.End),
		AllDay:          boolInt(input.AllDay),
		TimeZone:        input.TimeZone,
		Repeat:          string(input.Repeat),
		ReminderMinutes: nullMinutes(input.ReminderMinutes),
		ColorIndex:      int64(input.ColorIndex),
	}
}

// updateParams maps a validated input onto the update of event id.
func updateParams(id int64, input EventInput) db.UpdateCalendarEventParams {
	return db.UpdateCalendarEventParams{
		ID:              id,
		Title:           input.Title,
		Notes:           input.Notes,
		Location:        input.Location,
		StartsAt:        formatTime(input.Start),
		EndsAt:          formatTime(input.End),
		AllDay:          boolInt(input.AllDay),
		TimeZone:        input.TimeZone,
		Repeat:          string(input.Repeat),
		ReminderMinutes: nullMinutes(input.ReminderMinutes),
		ColorIndex:      int64(input.ColorIndex),
	}
}

// fromRow reads a stored row back as an Event owned by ownerName.
func fromRow(row db.CalendarEvent, ownerName string) (Event, error) {
	start, err := time.Parse(storedTimeLayout, row.StartsAt)
	if err != nil {
		return Event{}, fmt.Errorf("event %d start: %w", row.ID, err)
	}
	end, err := time.Parse(storedTimeLayout, row.EndsAt)
	if err != nil {
		return Event{}, fmt.Errorf("event %d end: %w", row.ID, err)
	}
	var reminder *int
	if row.ReminderMinutes.Valid {
		m := int(row.ReminderMinutes.Int64)
		reminder = &m
	}
	return Event{
		ID:              row.ID,
		CalendarID:      row.CalendarID,
		Title:           row.Title,
		Notes:           row.Notes,
		Location:        row.Location,
		Start:           start,
		End:             end,
		AllDay:          row.AllDay == 1,
		TimeZone:        row.TimeZone,
		Repeat:          Repeat(row.Repeat),
		ReminderMinutes: reminder,
		ColorIndex:      int(row.ColorIndex),
		OwnerID:         row.CreatedBy.Int64,
		OwnerName:       ownerName,
		CreatedAt:       row.CreatedAt,
		UpdatedAt:       row.UpdatedAt,
	}, nil
}
