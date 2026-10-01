package v0_calendar

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// deleteEvent godoc
// @Summary Delete a calendar event
// @Description Deletes an event, every occurrence of a repeating one included, and tells every open client it changed.
// @Tags calendar
// @Param id path int true "Event ID"
// @Success 204
// @Failure 400 {object} serverutil.Response "Bad Request: id is not a number"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /calendar/events/{id} [delete]
func deleteEvent(c *gin.Context) *serverutil.Response {
	id, ok := eventID(c)
	if !ok {
		return serverutil.BadRequest(errBadID)
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	if _, err := calendarutil.DeleteEvent(c.Request.Context(), calendarutil.DeleteEventParams{
		Queries: deps.Database().Queries,
		ID:      id,
	}); err != nil {
		return eventError(err)
	}
	publishChanged(deps, id)
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var deleteEventRoute = serverutil.ApiRoute(
	"DELETE", "/calendar/events/:id", deleteEvent,
)
