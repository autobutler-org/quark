package v0_admin

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/requestlogutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listAccountRequestHistory godoc
// @Summary List account request decisions
// @Description Returns the most recent approvals and denials of account requests, newest first: who asked, the outcome, which admin decided and when. The last 100 decisions are kept. Admin-only.
// @Tags admin
// @Produce json
// @Success 200 {array} requestlogutil.Entry
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/account-requests/history [get]
func listAccountRequestHistory(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	result, err := requestlogutil.List(c.Request.Context(), requestlogutil.ListParams{Queries: deps.Database().Queries})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result.Entries)
}

var listAccountRequestHistoryRoute = serverutil.ApiRoute("GET", "/admin/account-requests/history", listAccountRequestHistory)
