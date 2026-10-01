package v0_calendar

import (
	"database/sql"
	"errors"
	"strconv"
	"time"

	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// errEventNotFound is what a caller hears about an event that does not exist.
var errEventNotFound = errors.New("event not found")

// errBadID answers an id that is not a number.
var errBadID = errors.New("event id must be a number")

// eventID reads the :id path parameter.
func eventID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	return id, err == nil
}

// parseInstant reads an RFC 3339 time from a request, naming the field when it
// cannot.
func parseInstant(field, value string) (time.Time, error) {
	t, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return time.Time{}, errors.New(field + " must be an RFC 3339 time")
	}
	return t, nil
}

// toInput converts a request body into the service's input.
func toInput(req eventRequest) (calendarutil.EventInput, error) {
	start, err := parseInstant("start", req.Start)
	if err != nil {
		return calendarutil.EventInput{}, err
	}
	end, err := parseInstant("end", req.End)
	if err != nil {
		return calendarutil.EventInput{}, err
	}
	return calendarutil.EventInput{
		Title:           req.Title,
		Notes:           req.Notes,
		Location:        req.Location,
		Start:           start,
		End:             end,
		AllDay:          req.AllDay,
		TimeZone:        req.TimeZone,
		Repeat:          calendarutil.Repeat(req.Repeat),
		ReminderMinutes: req.ReminderMinutes,
		ColorIndex:      req.ColorIndex,
	}, nil
}

// toEventJSON converts a stored event for a response.
func toEventJSON(e calendarutil.Event) EventJSON {
	return EventJSON{
		ID:              e.ID,
		CalendarID:      e.CalendarID,
		Title:           e.Title,
		Notes:           e.Notes,
		Location:        e.Location,
		Start:           e.Start.UTC().Format(time.RFC3339),
		End:             e.End.UTC().Format(time.RFC3339),
		AllDay:          e.AllDay,
		TimeZone:        e.TimeZone,
		Repeat:          string(e.Repeat),
		ReminderMinutes: e.ReminderMinutes,
		ColorIndex:      e.ColorIndex,
		CreatedAt:       e.CreatedAt.UTC().Format(time.RFC3339),
		UpdatedAt:       e.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

// eventError maps a calendarutil error onto its status: 400 for a broken rule,
// 404 for a missing event, and 500 for anything else.
func eventError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, calendarutil.ErrInvalidEvent):
		return serverutil.BadRequest(err)
	case errors.Is(err, sql.ErrNoRows):
		return serverutil.NotFound(errEventNotFound)
	default:
		return serverutil.InternalServerError(err)
	}
}

// publishChanged tells every open client that event id changed, so each
// fetches the range it shows again.
func publishChanged(deps deputil.Dependencies, id int64) {
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventCalendarChanged, Data: id})
	}
}
