package v0_calendar

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// maxICalBytes bounds an imported .ics file.
const maxICalBytes = 8 << 20

// importICal godoc
// @Summary Import an iCalendar file
// @Description Adds the events of an .ics file, sent as the raw body in any content type, to the household calendar, owned by the caller (#1151), and tells every open client the calendar changed. Daily, weekly and monthly rules become the matching repeat, with COUNT or UNTIL as the last date and EXDATEs as skipped occurrences; a modified occurrence becomes a one-off its series skips. Yearly rules, intervals, extra BYDAY or BYMONTHDAY values, cancelled events, events that break a calendar rule, and events whose title, start, end and all-day flag match an existing one are skipped and counted, so importing a file twice adds nothing. Reminders are not imported. The body may be at most 8 MiB.
// @Tags calendar
// @Accept text/calendar
// @Produce json
// @Param body body string true "The iCalendar file"
// @Success 200 {object} ImportICalJSON
// @Failure 400 {object} serverutil.Response "Bad Request: the body is not an iCalendar file"
// @Failure 413 {object} serverutil.Response "Request Entity Too Large: the body is over 8 MiB"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /calendar/ical [post]
func importICal(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	result, err := calendarutil.ImportICal(c.Request.Context(), calendarutil.ImportICalParams{
		Database:  deps.Database(),
		Reader:    http.MaxBytesReader(c.Writer, c.Request.Body, maxICalBytes),
		CreatedBy: callerID(c),
	})
	if _, tooLarge := errors.AsType[*http.MaxBytesError](err); tooLarge {
		return serverutil.NewResponse().WithStatusCode(http.StatusRequestEntityTooLarge).WithError(errors.New("the file can be at most 8 MiB"))
	}
	if errors.Is(err, calendarutil.ErrInvalidICal) {
		return serverutil.BadRequest(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if result.Imported > 0 {
		publishChanged(deps, 0)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(ImportICalJSON{Imported: result.Imported, Skipped: result.Skipped})
}

var importICalRoute = serverutil.ApiRoute(
	"POST", "/calendar/ical", importICal,
)
