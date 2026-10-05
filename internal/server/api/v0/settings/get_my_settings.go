package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
	"github.com/gin-gonic/gin"
)

// getMySettings godoc
// @Summary Get your own settings
// @Description Returns the settings the caller chose for their own account. themeColor overrides the Quark's theme color; the empty string, which is also what an account that has chosen nothing gets, means follow the Quark.
// @Tags settings
// @Produce json
// @Success 200 {object} usersettingsutil.Settings
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/me [get]
func getMySettings(c *gin.Context) *serverutil.Response {
	userID, err := callerID(c)
	if err != nil {
		return serverutil.Unauthorized(err)
	}
	result, err := usersettingsutil.Load(usersettingsutil.LoadParams{DataDir: storageutil.GetDataDir(), UserID: userID})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result.Settings)
}

var getMySettingsRoute = serverutil.ApiRoute("GET", "/settings/me", getMySettings)
