package v0_calendar

import (
	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// exportICal godoc
// @Summary Export the calendar as iCalendar
// @Description Streams the household calendar as an RFC 5545 iCalendar file (#1151), one VEVENT per event with a stable UID. A repeating event carries its RRULE and the occurrences it skips as EXDATEs; reminders and colors are left out. The URL is also a subscription feed that Apple Calendar, Google Calendar and Thunderbird can poll, and it accepts ?token= in place of the Authorization header because those apps cannot send one; GET /calendar/ical/url hands out such a link.
// @Tags calendar
// @Produce text/calendar
// @Param token query string false "Session token, for a calendar app that cannot send an Authorization header"
// @Success 200 {file} file
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /calendar/ical [get]
func exportICal(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	c.Header("Content-Type", "text/calendar; charset=utf-8")
	c.Header("Content-Disposition", `attachment; filename="quark.ics"`)
	_, err := calendarutil.ExportICal(c.Request.Context(), calendarutil.ExportICalParams{
		Queries: deps.Database().Queries,
		Writer:  c.Writer,
	})
	if err != nil && !c.Writer.Written() {
		c.Writer.Header().Del("Content-Disposition")
		c.Writer.Header().Del("Content-Type")
		return serverutil.InternalServerError(err)
	}
	// Once the body has begun, an error can only cut it short.
	return nil
}

var exportICalRoute = serverutil.ApiRoute(
	"GET", "/calendar/ical", exportICal,
)
