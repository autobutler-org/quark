package v0_access

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listSharedWithMe godoc
// @Summary List what has been shared with you
// @Description Returns the root of each ad-hoc share the signed-in account holds, with the account or group that owns it, for the file browser's Shared with me shortcut. Left out are their own home and its contents, which My files opens; every group folder and its contents, which Groups opens; the users and groups folders themselves; the device root; the trash; and a grant inside another grant. An admin bypasses the access table, so their answer is empty and they reach everything through All files.
// @Tags access
// @Produce json
// @Success 200 {object} accessutil.ListSharedWithMeResult
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /access/mine [get]
func listSharedWithMe(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	access, err := accessutil.LoadRequest(c, database, deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	username, _ := ctxutil.Get[string](c, "username")

	result, err := accessutil.ListSharedWithMe(accessutil.ListSharedWithMeParams{
		Ctx:      c.Request.Context(),
		Database: database,
		Access:   access,
		Username: username,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listSharedWithMeRoute = serverutil.ApiRoute("GET", "/access/mine", listSharedWithMe)
