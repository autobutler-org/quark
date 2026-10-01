// Package v0_calendar serves /api/v0/calendar: the household calendar's events,
// which every signed-in account reads and writes (#1144). None of its routes are
// admin-only. A repeating event is served once, as its series; the client
// expands the occurrences.
package v0_calendar

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the router for /api/v0/calendar.
func NewRouter() serverutil.Router {
	return &router{}
}
