package v0_access

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listAccess godoc
// @Summary List who can reach a file or folder
// @Description Returns the grants on a path, then one inherited grant per account or group for the highest level a parent folder gives it; a grant whose from is not relPath is inherited and is changed on that folder. Only an owner of the path, directly or through a parent folder, or an admin may see them. canManage and canGrantOwner are true in every answer.
// @Tags access
// @Produce json
// @Param serial query string false "Device serial; empty is the internal device"
// @Param relPath query string true "Path on the device"
// @Success 200 {object} accessutil.GrantsResult
// @Failure 400 {object} serverutil.Response "a path in the trash"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller can read the path but doesn't own it"
// @Failure 404 {object} serverutil.Response "the caller can't read the path"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /access [get]
func listAccess(c *gin.Context) *serverutil.Response {
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

	result, err := accessutil.ListGrants(accessutil.ListGrantsParams{
		Ctx:          c.Request.Context(),
		Database:     database,
		Access:       access,
		DeviceSerial: c.Query("serial"),
		Path:         c.Query("relPath"),
	})
	if err != nil {
		return grantError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listAccessRoute = serverutil.ApiRoute("GET", "/access", listAccess)
