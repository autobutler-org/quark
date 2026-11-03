package v0_calendar

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// EventJSON is the JSON representation of a calendar event. For a repeating
// event, start and end are its first occurrence.
type EventJSON struct {
	ID         int64  `json:"id"`
	CalendarID int64  `json:"calendarId"`
	Title      string `json:"title"`
	Notes      string `json:"notes"`
	Location   string `json:"location"`
	// Start and End are RFC 3339 in UTC. For an all-day event they are
	// midnight UTC standing for the calendar date, and End is exclusive.
	Start    string `json:"start"`
	End      string `json:"end"`
	AllDay   bool   `json:"allDay"`
	TimeZone string `json:"timeZone"`
	// Repeat is none, daily, weekly or monthly.
	Repeat string `json:"repeat"`
	// RepeatUntil is a repeating event's last date, inclusive, as midnight
	// UTC standing for that calendar date; null repeats forever (#2524).
	RepeatUntil *string `json:"repeatUntil"`
	// ExcludedStarts are occurrence starts a series skips, RFC 3339 UTC.
	// Empty when it skips nothing (#3215).
	ExcludedStarts []string `json:"excludedStarts,omitempty"`
	// ReminderMinutes counts back from Start; null is no reminder.
	ReminderMinutes *int `json:"reminderMinutes"`
	ColorIndex      int  `json:"colorIndex"`
	// Owner is the username of the account that created the event, or empty
	// for an event with no owner (#2544).
	Owner string `json:"owner"`
	// Mine is true when the caller created the event.
	Mine      bool   `json:"mine"`
	CreatedAt string `json:"createdAt"`
	UpdatedAt string `json:"updatedAt"`
}

// EventListJSON is the response to a list of events.
type EventListJSON struct {
	Events []EventJSON `json:"events"`
}

// eventRequest is the body of a create or an update.
type eventRequest struct {
	Title    string `json:"title"`
	Notes    string `json:"notes"`
	Location string `json:"location"`
	// Start and End are RFC 3339. An all-day event sends midnight UTC.
	Start    string `json:"start" binding:"required"`
	End      string `json:"end" binding:"required"`
	AllDay   bool   `json:"allDay"`
	TimeZone string `json:"timeZone"`
	// Repeat is none, daily, weekly or monthly; empty is none.
	Repeat string `json:"repeat"`
	// RepeatUntil is the last date a repeating event occurs on, inclusive,
	// as midnight UTC. Null or absent repeats forever; a one-off event
	// ignores it.
	RepeatUntil *string `json:"repeatUntil"`
	// ExcludedStarts are occurrence starts a series skips, RFC 3339 UTC.
	// Absent skips nothing. A one-off event ignores them (#3215).
	ExcludedStarts  []string `json:"excludedStarts,omitempty"`
	ReminderMinutes *int     `json:"reminderMinutes"`
	ColorIndex      int      `json:"colorIndex"`
}

// moveRequest is the body of a move of one occurrence, or of the series.
type moveRequest struct {
	// Scope is one, following or all.
	Scope           string `json:"scope"`
	OccurrenceStart string `json:"occurrenceStart"`
	Start           string `json:"start"`
	End             string `json:"end"`
}

// MoveJSON is the series after a move, plus the one-off or new series when
// the move created one.
type MoveJSON struct {
	Series  EventJSON  `json:"series"`
	Created *EventJSON `json:"created,omitempty"`
}

// ICalURLJSON is the calendar's subscription link (#1151).
type ICalURLJSON struct {
	URL string `json:"url"`
}

// ImportICalJSON counts the events an iCalendar import stored and skipped.
type ImportICalJSON struct {
	Imported int `json:"imported"`
	Skipped  int `json:"skipped"`
}

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listEventsRoute,
		getEventRoute,
		createEventRoute,
		updateEventRoute,
		moveEventRoute,
		deleteEventRoute,
		exportICalRoute,
		getICalURLRoute,
		importICalRoute,
	}
}
