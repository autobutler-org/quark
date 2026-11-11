package v0_admin

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/restartutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/updateutil"

	"github.com/gin-gonic/gin"
)

// restartQuark godoc
// @Summary Restart Quark
// @Description Restarts Quark. The response goes out first; the process exits about two seconds later, its supervisor starts it again, and it is unavailable for a few seconds. Admin-only.
// @Tags admin
// @Success 200
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "Nothing would start Quark again, or an update or restart is already in progress"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/restart [post]
func restartQuark(_ *gin.Context) *serverutil.Response {
	if _, err := restartutil.Restart(restartutil.RestartParams{}); err != nil {
		if errors.Is(err, restartutil.ErrUnsupervised) || errors.Is(err, updateutil.ErrUpdateInProgress) {
			return serverutil.Conflict(err)
		}
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok()
}

var restartQuarkRoute = serverutil.ApiRoute("POST", "/admin/restart", restartQuark)
