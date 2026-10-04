package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// getPublicSettings godoc
// @Summary Get the Quark's public settings
// @Description Returns the Quark's settings that are safe to show before sign-in. Needs no session, so the sign-in page can read them. themeColor is the theme color an admin chose for the Quark, a preset name or a lowercase #rrggbb color, or the empty string when no admin has chosen.
// @Tags settings
// @Produce json
// @Success 200 {object} PublicSettingsResponse
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /settings/public [get]
func getPublicSettings(_ *gin.Context) *serverutil.Response {
	s, err := settingsutil.Load()
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(PublicSettingsResponse{ThemeColor: s.ThemeColor})
}

var getPublicSettingsRoute = serverutil.ApiRoute("GET", "/settings/public", getPublicSettings)
