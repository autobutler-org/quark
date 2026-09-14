package v0_settings

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// updateAccessRequests godoc
// @Summary Turn account requests on or off
// @Description Sets whether people can request an account from the sign-in page. Requests are on until an admin turns them off. Admin-only.
// @Tags settings
// @Accept json
// @Produce json
// @Param body body accessRequestsSetting true "Whether account requests are on"
// @Success 200 {object} accessRequestsSetting
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /settings/access-requests [put]
func updateAccessRequests(c *gin.Context) *serverutil.Response {
	var body accessRequestsSetting
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	if err := settingsutil.SetAccessRequestsEnabled(*body.Enabled); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(body)
}

var updateAccessRequestsRoute = serverutil.ApiRoute("PUT", "/settings/access-requests", updateAccessRequests)
