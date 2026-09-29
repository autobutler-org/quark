package v0_calendar

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// updateEvent godoc
// @Summary Update a calendar event
// @Description Replaces every field of an event, under the same rules as a create, and tells every open client it changed. For a repeating event the change applies to the whole series.
// @Tags calendar
// @Accept json
// @Produce json
// @Param id path int true "Event ID"
// @Param body body eventRequest true "The event's new fields"
// @Success 200 {object} EventJSON
// @Failure 400 {object} serverutil.Response "Bad Request: a malformed id or body, or an event that breaks a rule"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /calendar/events/{id} [put]
func updateEvent(c *gin.Context) *serverutil.Response {
	id, ok := eventID(c)
	if !ok {
		return serverutil.BadRequest(errBadID)
	}
	var req eventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("start and end are required"))
	}
	input, err := toInput(req)
	if err != nil {
		return serverutil.BadRequest(err)
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	result, err := calendarutil.UpdateEvent(c.Request.Context(), calendarutil.UpdateEventParams{
		Queries: deps.Database().Queries,
		ID:      id,
		Input:   input,
	})
	if err != nil {
		return eventError(err)
	}
	publishChanged(deps, id)
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(toEventJSON(result.Event))
}

var updateEventRoute = serverutil.ApiRoute(
	"PUT", "/calendar/events/:id", updateEvent,
)
