package v0_calendar

import (
	"errors"
	"net/url"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getICalURL godoc
// @Summary Get the calendar's subscription link
// @Description Returns a link to GET /calendar/ical that a calendar app (Apple Calendar, Google Calendar, Thunderbird) can subscribe to (#1151). The link carries the caller's own session token as ?token=, which the subscribing app presents on every fetch and which stays alive as long as it is used; signing that session out ends the subscription. A request signed in some other way than a session (Basic, a download token) has no token to hand out and is a 404.
// @Tags calendar
// @Produce json
// @Success 200 {object} ICalURLJSON
// @Failure 404 {object} serverutil.Response "Not Found: the request carries no session"
// @Security BearerAuth
// @Router /calendar/ical/url [get]
func getICalURL(c *gin.Context) *serverutil.Response {
	token, _ := ctxutil.Get[string](c, "sessionToken")
	if token == "" {
		return serverutil.NotFound(errors.New("a signed-in session is needed for a subscription link"))
	}
	scheme := "http"
	if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	link := url.URL{Scheme: scheme, Host: c.Request.Host, Path: "/api/v0/calendar/ical", RawQuery: url.Values{"token": {token}}.Encode()}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(ICalURLJSON{URL: link.String()})
}

var getICalURLRoute = serverutil.ApiRoute(
	"GET", "/calendar/ical/url", getICalURL,
)
