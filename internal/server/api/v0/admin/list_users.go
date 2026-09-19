package v0_admin

import (
	"errors"
	"fmt"
	"time"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listUsers godoc
// @Summary List all users
// @Description Returns all registered users. Admin-only.
// @Tags admin
// @Produce json
// @Success 200 {array} userSummary
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Router /admin/users [get]
func listUsers(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}

	rows, err := database.Queries.ListUsers(c.Request.Context())
	if err != nil {
		return serverutil.InternalServerError(fmt.Errorf("list users: %w", err))
	}

	summaries := make([]userSummary, 0, len(rows))
	for _, u := range rows {
		summaries = append(summaries, userSummary{
			ID:        u.ID,
			Username:  u.Username,
			IsAdmin:   u.IsAdmin != 0,
			Status:    u.Status,
			CreatedAt: u.CreatedAt.Format(time.RFC3339),
		})
	}

	return serverutil.Ok().WithData(summaries)
}

var listUsersRoute = serverutil.ApiRoute("GET", "/admin/users", listUsers)
