package v0_access

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listPrincipals godoc
// @Summary List who a file or folder can be shared with
// @Description Returns every active account by username and every group, the built-in everyone group first. Any signed-in account may ask, so each account carries only its id and username.
// @Tags access
// @Produce json
// @Success 200 {object} accessutil.ListPrincipalsResult
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /access/principals [get]
func listPrincipals(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}

	result, err := accessutil.ListPrincipals(accessutil.ListPrincipalsParams{
		Ctx:      c.Request.Context(),
		Database: database,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listPrincipalsRoute = serverutil.ApiRoute("GET", "/access/principals", listPrincipals)
