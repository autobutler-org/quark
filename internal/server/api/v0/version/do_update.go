package v0_version

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/updateutil"

	"github.com/gin-gonic/gin"
)

type UpdateRequest struct {
	Version string `json:"version"`
}

// doUpdate godoc
// @Summary Perform update
// @Description Performs an update to the specified version
// @Tags version
// @Accept json
// @Produce json
// @Param update body UpdateParams true "Update Request"
// @Success 200 {object} UpdateRequest
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /version/update [post]
func doUpdate(c *gin.Context) *serverutil.Response {
	params := UpdateParams{}
	if err := c.ShouldBind(&params); err != nil {
		return serverutil.BadRequest(err)
	}
	if params.Version == "" {
		return serverutil.BadRequest(
			errors.New("version parameter is required"),
		)
	}

	if err := updateutil.Update(params.Source, params.Version); err != nil {
		return serverutil.InternalServerError(err)
	}

	go restartQuark()
	return serverutil.Ok().WithData(params)
}

var doUpdateRoute = serverutil.ApiRoute(
	"POST", "/version/update", doUpdate,
)
