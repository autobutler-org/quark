package v0_admin

import (
	"errors"
	"fmt"
	"time"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listUsers godoc
// @Summary List all users
// @Description Returns all registered users. Admin-only. shortRecoveryPhrase is true for an account whose recovery key's phrase had fewer than 16 words or an unknown count (a key stored before #3183), the accounts still to rotate; an account with no recovery key reads false.
// @Tags admin
// @Produce json
// @Success 200 {array} userSummary
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
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
			ID:                  u.ID,
			Username:            u.Username,
			IsAdmin:             u.IsAdmin != 0,
			Status:              u.Status,
			CreatedAt:           u.CreatedAt.Format(time.RFC3339),
			ShortRecoveryPhrase: authutil.IsShortRecoveryPhrase(u.HasRecoveryKey, u.RecoveryPhraseWords),
		})
	}

	return serverutil.Ok().WithData(summaries)
}

var listUsersRoute = serverutil.ApiRoute("GET", "/admin/users", listUsers)
