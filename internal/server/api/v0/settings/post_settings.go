package v0_settings

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// postSettings godoc
// @Summary Update settings
// @Description Updates application settings
// @Tags settings
// @Accept json
// @Produce json
// @Param settings body SettingsJSON true "Settings"
// @Success 200 {object} SettingsJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings [post]
func postSettings(c *gin.Context) *serverutil.Response {
	var body SettingsJSON
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}

	if err := settingsutil.SetAutoUpdate(body.AutoUpdate); err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithData(SettingsJSON{
		AutoUpdate: body.AutoUpdate,
	})
}

var postSettingsRoute = serverutil.ApiRoute("POST", "/settings", postSettings)
