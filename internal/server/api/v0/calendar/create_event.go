package v0_calendar

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// createEvent godoc
// @Summary Create a calendar event
// @Description Adds an event to the household calendar, owned by the caller, and tells every open client it changed. Times are RFC 3339; an all-day event starts and ends at midnight UTC, the end exclusive. repeat is none, daily, weekly or monthly, and a repeating event must end before it repeats. repeatUntil is a repeating event's last date, inclusive, sent as midnight UTC; it may not fall before the first occurrence's date, null or absent repeats forever, and a one-off event ignores it. reminderMinutes counts back from the start, 0 to a week; an all-day event's may be negative down to -1439 so it falls on its own day (-540 is 9 AM). colorIndex is 0 to 5. timeZone is the IANA zone the event was made in, like America/New_York, or empty when the client does not know it; any other name is a 400.
// @Tags calendar
// @Accept json
// @Produce json
// @Param body body eventRequest true "The event"
// @Success 201 {object} EventJSON
// @Failure 400 {object} serverutil.Response "Bad Request: a malformed body or an event that breaks a rule"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /calendar/events [post]
func createEvent(c *gin.Context) *serverutil.Response {
	var req eventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(bindError(err))
	}
	input, err := toInput(req)
	if err != nil {
		return serverutil.BadRequest(err)
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	result, err := calendarutil.CreateEvent(c.Request.Context(), calendarutil.CreateEventParams{
		Queries:   deps.Database().Queries,
		Input:     input,
		CreatedBy: callerID(c),
	})
	if err != nil {
		return eventError(err)
	}
	publishChanged(deps, result.Event.ID)
	return serverutil.Ok().WithStatusCode(http.StatusCreated).WithContentType(serverutil.ContentTypeJSON).WithData(toEventJSON(result.Event, callerID(c)))
}

var createEventRoute = serverutil.ApiRoute(
	"POST", "/calendar/events", createEvent,
)
