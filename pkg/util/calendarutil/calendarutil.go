// Package calendarutil holds the household calendar's events (#1144): creating,
// reading, listing, updating and deleting them, and the rules an event must
// meet to be stored.
//
// Every event belongs to the default calendar, Personal, which every signed-in
// account reads and writes. A repeating event is stored once, as its first
// occurrence and a preset (daily, weekly or monthly); the app expands the
// occurrences in the viewer's local time, so ListEvents returns series, not
// occurrences. A series repeats forever unless it has a RepeatUntil date
// (#2524), and ListEvents leaves out a series that ended before the range.
// ExcludedStarts are occurrence starts the series skips (#3215). Moving one
// occurrence records that start and stores the new time as its own event.
// Moving that occurrence and every one after it ends the series the day
// before and starts a new series.
//
// With no app open, ExpandEvent turns a series into occurrences in the
// event's own time zone, and ListReminders finds the reminders that fall due
// in a span of time (#2525): what a push worker asks.
//
// ExportICal writes the calendar as an RFC 5545 iCalendar feed that calendar
// apps subscribe to, and ImportICal stores the events of an .ics file,
// mapping each rule onto the presets above and skipping what they cannot
// express (#1151).
//
// An event belongs to the account that created it (#2544), which lets the
// calendar be narrowed to one person. It is not privacy: every account still
// sees and edits every event.
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
	"io"
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
	// picks one of them. Migration 025 repeats this and the reminder bounds
	// below as CHECKs on calendar_events: change them together.
	ColorCount = 6
	// MaxReminderMinutes is a week before the start.
	MaxReminderMinutes = 7 * 24 * 60
	// MinAllDayReminderMinutes lets an all-day event's reminder fall on its
	// own day, up to a minute before midnight: -540 is 9 AM on the day.
	MinAllDayReminderMinutes = -(24*60 - 1)
	// MaxListRange bounds one ListEvents call.
	MaxListRange = 400 * 24 * time.Hour
	// MaxExcludedStarts is how many occurrence starts one series may skip.
	MaxExcludedStarts = 100
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
	// it, and empty when it does not; any other name is rejected. ExpandEvent
	// steps a series' occurrences in it.
	TimeZone string
	// Repeat is RepeatNone when empty.
	Repeat Repeat
	// RepeatUntil is the last date an occurrence may start on, inclusive:
	// midnight UTC standing for that calendar date, like an all-day date. Nil
	// repeats forever. It must not fall before the first occurrence's date,
	// and a one-off event drops it.
	RepeatUntil *time.Time
	// ReminderMinutes counts back from Start; nil is no reminder.
	ReminderMinutes *int
	ColorIndex      int
	// ExcludedStarts are occurrence starts a series skips, UTC to the second.
	// Nil on a one-off event and on a series that skips nothing.
	ExcludedStarts []time.Time
}

// Event is a stored event, or the first occurrence of a repeating one.
type Event struct {
	ID         int64
	CalendarID int64
	Title      string
	Notes      string
	Location   string
	Start      time.Time
	End        time.Time
	AllDay     bool
	TimeZone   string
	Repeat     Repeat
	// RepeatUntil is the series' last date, or nil when it repeats forever.
	RepeatUntil     *time.Time
	ReminderMinutes *int
	ColorIndex      int
	// OwnerID is the account that created the event, or 0 for an event made
	// before owners were recorded or whose account was deleted.
	OwnerID int64
	// OwnerName is that account's username, or empty with no owner.
	OwnerName string
	CreatedAt time.Time
	UpdatedAt time.Time
	// ExcludedStarts are the occurrence starts this series skips (#3215).
	ExcludedStarts []time.Time
}

// CreateEventParams adds an event to the default calendar.
type CreateEventParams struct {
	Queries db.Querier
	Input   EventInput
	// CreatedBy is the account creating the event, which owns it; 0 for none.
	CreatedBy int64
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
	insert := createParams(calendar.ID, input)
	if params.CreatedBy != 0 {
		insert.CreatedBy = sql.NullInt64{Int64: params.CreatedBy, Valid: true}
	}
	row, err := params.Queries.CreateCalendarEvent(ctx, insert)
	if err != nil {
		return CreateEventResult{}, err
	}
	// Read it back for the owner's name, which the insert cannot return.
	got, err := GetEvent(ctx, GetEventParams{Queries: params.Queries, ID: row.ID})
	return CreateEventResult(got), err
}

// GetEventParams reads one event.
type GetEventParams struct {
	Queries db.Querier
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
	event, err := fromRow(row.CalendarEvent, row.OwnerName)
	return GetEventResult{Event: event}, err
}

// ListEventsParams lists the events that may have an occurrence in [From, To).
type ListEventsParams struct {
	Queries db.Querier
	From    time.Time
	To      time.Time
}

// ListEventsResult carries the events, by start.
type ListEventsResult struct {
	Events []Event
}

// ListEvents lists the one-off events overlapping [From, To) and every
// repeating event with an occurrence there, however long ago its series began
// (#2535); a series that ended before the range is left out. The range is widened by a day each way so an all-day event, whose
// date means midnight wherever it is read, is not missed at the edges, and so
// a series the app expands in local time is not missed either; the app
// narrows it again.
func ListEvents(ctx context.Context, params ListEventsParams) (ListEventsResult, error) {
	if err := checkRange(params.From, params.To); err != nil {
		return ListEventsResult{}, err
	}
	events, err := listEvents(ctx, params.Queries, params.From, params.To)
	return ListEventsResult{Events: events}, err
}

// UpdateEventParams replaces an event's fields. For a repeating event that is
// the whole series, exclusions included. One occurrence moves through
// MoveEvent, which keeps this row and stores the new time beside it. The
// owner stays the account that created it, whoever edits it.
type UpdateEventParams struct {
	Queries db.Querier
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
	if _, err := params.Queries.UpdateCalendarEvent(ctx, updateParams(params.ID, input)); err != nil {
		return UpdateEventResult{}, err
	}
	got, err := GetEvent(ctx, GetEventParams{Queries: params.Queries, ID: params.ID})
	return UpdateEventResult(got), err
}

// DeleteEventParams deletes an event, every occurrence of it included.
type DeleteEventParams struct {
	Queries db.Querier
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

// How much of a repeating event a drag moves (#3215).
const (
	// MoveThisEvent skips that occurrence and stores the new time as a one-off.
	MoveThisEvent = "one"
	// MoveFollowing ends the series the day before that occurrence and starts
	// a new series at the new time. The first occurrence moves the whole series.
	MoveFollowing = "following"
	// MoveAllEvents moves every occurrence, the series' own start included.
	MoveAllEvents = "all"
)

// MoveEventParams moves the occurrence of ID that starts at OccurrenceStart
// so that it runs from Start to End. Scope is MoveThisEvent, MoveFollowing
// or MoveAllEvents.
type MoveEventParams struct {
	Database        *db.DatabaseSqlc
	ID              int64
	Scope           string
	OccurrenceStart time.Time
	Start           time.Time
	End             time.Time
}

// MoveEventResult carries the original series after the move. Created is the
// one-off or the new series, and nil when the move only changed the original.
type MoveEventResult struct {
	Series  Event
	Created *Event
}

// MoveEvent applies Scope to one repeating event. The series and anything it
// creates commit together. A missing event is sql.ErrNoRows.
func MoveEvent(ctx context.Context, params MoveEventParams) (MoveEventResult, error) {
	if params.Database == nil || params.Database.Db == nil {
		return MoveEventResult{}, errors.New("calendar move needs a database")
	}
	var result MoveEventResult
	err := db.InTx(ctx, params.Database.Db, func(q db.Querier) error {
		var err error
		result, err = moveEvent(ctx, q, params)
		return err
	})
	return result, err
}

// ErrInvalidICal reports an import body that is not an iCalendar file: it has
// no BEGIN:VCALENDAR.
var ErrInvalidICal = errors.New("not an iCalendar file")

// ExportICalParams writes the default calendar to Writer.
type ExportICalParams struct {
	Queries db.Querier
	Writer  io.Writer
}

// ExportICalResult counts the events written.
type ExportICalResult struct {
	Events int
}

// ExportICal writes the default calendar to Writer as an RFC 5545 VCALENDAR,
// one VEVENT per stored event, streamed event by event. Each event's UID is
// stable, so a subscribing app updates an event rather than adding it again.
// A series' preset becomes its RRULE and its skipped starts EXDATEs.
// Reminders and colors are not exported.
func ExportICal(ctx context.Context, params ExportICalParams) (ExportICalResult, error) {
	calendar, err := params.Queries.GetDefaultCalendar(ctx)
	if err != nil {
		return ExportICalResult{}, err
	}
	rows, err := params.Queries.ListCalendarEvents(ctx, calendar.ID)
	if err != nil {
		return ExportICalResult{}, err
	}
	return ExportICalResult{Events: len(rows)}, writeICal(params.Writer, calendar.Name, rows)
}

// ImportICalParams stores the events of the iCalendar on Reader, owned by
// CreatedBy (0 for none). The caller bounds the reader's size.
type ImportICalParams struct {
	Database  *db.DatabaseSqlc
	Reader    io.Reader
	CreatedBy int64
}

// ImportICalResult counts the events stored and the ones left out.
type ImportICalResult struct {
	Imported int
	Skipped  int
}

// ImportICal stores every VEVENT on Reader on the default calendar, in one
// transaction. A rule the presets cannot express (yearly, an interval, more
// than the start's own weekday or day of the month), a cancelled event, one
// that breaks an event rule, and one matching an existing event's title,
// start, end and all-day flag are skipped, so importing a file twice adds
// nothing. A modified occurrence (RECURRENCE-ID) is stored as a one-off and
// skipped by its series. A body with no VCALENDAR is ErrInvalidICal.
func ImportICal(ctx context.Context, params ImportICalParams) (ImportICalResult, error) {
	if params.Database == nil || params.Database.Db == nil {
		return ImportICalResult{}, errors.New("calendar import needs a database")
	}
	events, err := parseICal(params.Reader)
	if err != nil {
		return ImportICalResult{}, err
	}
	var result ImportICalResult
	err = db.InTx(ctx, params.Database.Db, func(q db.Querier) error {
		var err error
		result, err = storeICalEvents(ctx, q, events, params.CreatedBy)
		return err
	})
	return result, err
}
