package v0_settings

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
	"github.com/gin-gonic/gin"
)

// updateThemeColor godoc
// @Summary Set the Quark's theme color
// @Description Sets the theme color for everyone on the Quark who has not chosen their own, and publishes public_settings_changed. themeColor is a preset name (a lowercase letter, then up to 31 lowercase letters, digits or hyphens) or a custom color as lowercase #rrggbb; the empty string clears it. Only the shape is checked: the Quark keeps no list of preset names. Admin-only.
// @Tags settings
// @Accept json
// @Produce json
// @Param body body themeColorSetting true "The theme color"
// @Success 200 {object} PublicSettingsResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/theme-color [put]
func updateThemeColor(c *gin.Context) *serverutil.Response {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, usersettingsutil.MaxRequestBytes)
	var body themeColorSetting
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	err := settingsutil.SetThemeColor(*body.ThemeColor)
	if errors.Is(err, settingsutil.ErrInvalidThemeColor) {
		return serverutil.BadRequest(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps"); ok && deps.EventBus() != nil {
		deps.EventBus().Publish(eventbus.Event{Kind: eventbus.EventPublicSettingsChanged})
	}
	return serverutil.Ok().WithData(PublicSettingsResponse{ThemeColor: *body.ThemeColor})
}

var updateThemeColorRoute = serverutil.ApiRoute("PUT", "/settings/theme-color", updateThemeColor)
