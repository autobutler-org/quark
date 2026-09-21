package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// getSettings godoc
// @Summary Get settings
// @Description Retrieves application settings
// @Tags settings
// @Produce json
// @Success 200 {object} SettingsJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings [get]
func getSettings(c *gin.Context) *serverutil.Response {
	s, err := settingsutil.Load()
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(SettingsJSON{
		AutoUpdate: s.AutoUpdate,
	})
}

var getSettingsRoute = serverutil.ApiRoute("GET", "/settings", getSettings)
