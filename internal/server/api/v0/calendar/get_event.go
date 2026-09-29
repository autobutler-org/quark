package v0_calendar

import (
	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getEvent godoc
// @Summary Get a calendar event
// @Description Returns one event of the household calendar. A repeating event is returned as its series.
// @Tags calendar
// @Produce json
// @Param id path int true "Event ID"
// @Success 200 {object} EventJSON
// @Failure 400 {object} serverutil.Response "Bad Request: id is not a number"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /calendar/events/{id} [get]
func getEvent(c *gin.Context) *serverutil.Response {
	id, ok := eventID(c)
	if !ok {
		return serverutil.BadRequest(errBadID)
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	result, err := calendarutil.GetEvent(c.Request.Context(), calendarutil.GetEventParams{
		Queries: deps.Database().Queries,
		ID:      id,
	})
	if err != nil {
		return eventError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(toEventJSON(result.Event, callerID(c)))
}

var getEventRoute = serverutil.ApiRoute(
	"GET", "/calendar/events/:id", getEvent,
)
