// Package calendarutil holds the household calendar's events (#1144): creating,
// reading, listing, updating and deleting them, and the rules an event must
// meet to be stored.
//
// Every event belongs to the default calendar, Personal, which every signed-in
// account reads and writes. A repeating event is stored once, as its first
// occurrence and a preset (daily, weekly or monthly); the app expands the
// occurrences in the viewer's local time, so ListEvents returns series, not
// occurrences.
//
// A timed event's Start and End are instants. An all-day event's are dates:
// midnight UTC standing for that calendar date in every time zone, with End
// exclusive. HTTP concerns stay with the caller, which maps ErrInvalidEvent
// (and sql.ErrNoRows for a missing event) onto status codes.
package calendarutil

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// Repeat is how an event repeats: never, or a simple preset.
type Repeat string

// The repeat presets. Weekly keeps the weekday of the first occurrence and
// monthly its day of the month; a month without that day is skipped.
const (
	RepeatNone    Repeat = "none"
	RepeatDaily   Repeat = "daily"
	RepeatWeekly  Repeat = "weekly"
	RepeatMonthly Repeat = "monthly"
)

// The limits an event is held to.
const (
	MaxTitleLength    = 200
	MaxLocationLength = 500
	MaxNotesLength    = 10000
	MaxTimeZoneLength = 64
	// ColorCount is the number of event colors the app offers; ColorIndex
	// picks one of them.
	ColorCount = 6
	// MaxReminderMinutes is a week before the start.
	MaxReminderMinutes = 7 * 24 * 60
	// MinAllDayReminderMinutes lets an all-day event's reminder fall on its
	// own day, up to a minute before midnight: -540 is 9 AM on the day.
	MinAllDayReminderMinutes = -(24*60 - 1)
	// MaxListRange bounds one ListEvents call.
	MaxListRange = 400 * 24 * time.Hour
)

// ErrInvalidEvent reports an event that breaks one of the rules above. It is
// wrapped with the rule that failed, and that text is the copy a client shows.
var ErrInvalidEvent = errors.New("invalid event")

// EventInput is what a caller sets on an event, for a create or an update.
type EventInput struct {
	Title    string
	Notes    string
	Location string
	Start    time.Time
	End      time.Time
	AllDay   bool
	// TimeZone is the IANA zone the event was made in, when the client knows
	// it. It is recorded for server-side reminders later (#2525) and not used
	// yet.
	TimeZone string
	// Repeat is RepeatNone when empty.
	Repeat Repeat
	// ReminderMinutes counts back from Start; nil is no reminder.
	ReminderMinutes *int
	ColorIndex      int
}

// Event is a stored event, or the first occurrence of a repeating one.
type Event struct {
	ID              int64
	CalendarID      int64
	Title           string
	Notes           string
	Location        string
	Start           time.Time
	End             time.Time
	AllDay          bool
	TimeZone        string
	Repeat          Repeat
	ReminderMinutes *int
	ColorIndex      int
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// CreateEventParams adds an event to the default calendar.
type CreateEventParams struct {
	Queries *db.Queries
	Input   EventInput
}

// CreateEventResult carries the created event.
type CreateEventResult struct {
	Event Event
}

// CreateEvent validates Input and stores it on the default calendar.
func CreateEvent(ctx context.Context, params CreateEventParams) (CreateEventResult, error) {
	input, err := validate(params.Input)
	if err != nil {
		return CreateEventResult{}, err
	}
	calendar, err := params.Queries.GetDefaultCalendar(ctx)
	if err != nil {
		return CreateEventResult{}, err
	}
	row, err := params.Queries.CreateCalendarEvent(ctx, createParams(calendar.ID, input))
	if err != nil {
		return CreateEventResult{}, err
	}
	event, err := fromRow(row)
	return CreateEventResult{Event: event}, err
}

// GetEventParams reads one event.
type GetEventParams struct {
	Queries *db.Queries
	ID      int64
}

// GetEventResult carries the event.
type GetEventResult struct {
	Event Event
}

// GetEvent reads one event. A missing one is sql.ErrNoRows.
func GetEvent(ctx context.Context, params GetEventParams) (GetEventResult, error) {
	row, err := params.Queries.GetCalendarEvent(ctx, params.ID)
	if err != nil {
		return GetEventResult{}, err
	}
	event, err := fromRow(row)
	return GetEventResult{Event: event}, err
}

// ListEventsParams lists the events that may have an occurrence in [From, To).
type ListEventsParams struct {
	Queries *db.Queries
	From    time.Time
	To      time.Time
}

// ListEventsResult carries the events, by start.
type ListEventsResult struct {
	Events []Event
}

// ListEvents lists the one-off events overlapping [From, To) and every
// repeating event whose series starts before To. The range is widened by a
// day each way so an all-day event, whose date means midnight wherever it is
// read, is not missed at the edges; the app narrows it again.
func ListEvents(ctx context.Context, params ListEventsParams) (ListEventsResult, error) {
	if !params.To.After(params.From) {
		return ListEventsResult{}, invalid("the range must end after it starts")
	}
	if params.To.Sub(params.From) > MaxListRange {
		return ListEventsResult{}, invalid("the range can span at most 400 days")
	}
	calendar, err := params.Queries.GetDefaultCalendar(ctx)
	if err != nil {
		return ListEventsResult{}, err
	}
	rows, err := params.Queries.ListCalendarEventsInRange(ctx, db.ListCalendarEventsInRangeParams{
		CalendarID: calendar.ID,
		RangeStart: formatTime(params.From.Add(-24 * time.Hour)),
		RangeEnd:   formatTime(params.To.Add(24 * time.Hour)),
	})
	if err != nil {
		return ListEventsResult{}, err
	}
	events := make([]Event, 0, len(rows))
	for _, row := range rows {
		event, err := fromRow(row)
		if err != nil {
			return ListEventsResult{}, err
		}
		events = append(events, event)
	}
	return ListEventsResult{Events: events}, nil
}

// UpdateEventParams replaces an event's fields. For a repeating event that is
// the whole series: the MVP has no per-occurrence edits.
type UpdateEventParams struct {
	Queries *db.Queries
	ID      int64
	Input   EventInput
}

// UpdateEventResult carries the updated event.
type UpdateEventResult struct {
	Event Event
}

// UpdateEvent validates Input and replaces the event's fields with it. A
// missing event is sql.ErrNoRows.
func UpdateEvent(ctx context.Context, params UpdateEventParams) (UpdateEventResult, error) {
	input, err := validate(params.Input)
	if err != nil {
		return UpdateEventResult{}, err
	}
	row, err := params.Queries.UpdateCalendarEvent(ctx, updateParams(params.ID, input))
	if err != nil {
		return UpdateEventResult{}, err
	}
	event, err := fromRow(row)
	return UpdateEventResult{Event: event}, err
}

// DeleteEventParams deletes an event, every occurrence of it included.
type DeleteEventParams struct {
	Queries *db.Queries
	ID      int64
}

// DeleteEventResult is empty: a delete either happened or returned an error.
type DeleteEventResult struct{}

// DeleteEvent deletes the event. A missing event is sql.ErrNoRows.
func DeleteEvent(ctx context.Context, params DeleteEventParams) (DeleteEventResult, error) {
	n, err := params.Queries.DeleteCalendarEvent(ctx, params.ID)
	if err != nil {
		return DeleteEventResult{}, err
	}
	if n == 0 {
		return DeleteEventResult{}, sql.ErrNoRows
	}
	return DeleteEventResult{}, nil
}
