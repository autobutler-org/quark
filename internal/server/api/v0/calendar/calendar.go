// Package v0_calendar serves /api/v0/calendar: the household calendar's events,
// which every signed-in account reads and writes (#1144). None of its routes are
// admin-only. A repeating event is served once, as its series; the client
// expands the occurrences. A repeating event can skip occurrence starts, and
// one occurrence can be moved on its own or together with every one after it.
// Each event names the account that created it and
// says whether that is the caller (#2544), so a client can narrow the calendar
// by person. GET /calendar/ical exports the calendar as iCalendar and doubles
// as a subscription feed, GET /calendar/ical/url hands out that feed's link,
// and POST /calendar/ical imports an .ics file (#1151).
package v0_calendar

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the router for /api/v0/calendar.
func NewRouter() serverutil.Router {
	return &router{}
}
