package v0_calendar

import (
	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listEvents godoc
// @Summary List calendar events in a range
// @Description Lists the household calendar's one-off events that overlap [from, to) and every repeating event with an occurrence there, by start. A repeating event is listed once, as its first occurrence and preset; the client expands the occurrences. The range is widened by a day each way so all-day events are not missed at its edges, and can span at most 400 days.
// @Tags calendar
// @Produce json
// @Param from query string true "Range start, RFC 3339"
// @Param to query string true "Range end (exclusive), RFC 3339"
// @Success 200 {object} EventListJSON
// @Failure 400 {object} serverutil.Response "Bad Request: missing or malformed from/to, or a reversed or too-long range"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /calendar/events [get]
func listEvents(c *gin.Context) *serverutil.Response {
	from, err := parseInstant("from", c.Query("from"))
	if err != nil {
		return serverutil.BadRequest(err)
	}
	to, err := parseInstant("to", c.Query("to"))
	if err != nil {
		return serverutil.BadRequest(err)
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	result, err := calendarutil.ListEvents(c.Request.Context(), calendarutil.ListEventsParams{
		Queries: deps.Database().Queries,
		From:    from,
		To:      to,
	})
	if err != nil {
		return eventError(err)
	}

	events := make([]EventJSON, 0, len(result.Events))
	for _, e := range result.Events {
		events = append(events, toEventJSON(e, callerID(c)))
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(EventListJSON{Events: events})
}

var listEventsRoute = serverutil.ApiRoute(
	"GET", "/calendar/events", listEvents,
)
