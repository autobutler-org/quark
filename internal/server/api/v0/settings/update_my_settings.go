package v0_settings

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
	"github.com/gin-gonic/gin"
)

// updateMySettings godoc
// @Summary Replace your own settings
// @Description Replaces the settings of the caller's own account with the body. themeColor is a preset name (a lowercase letter, then up to 31 lowercase letters, digits or hyphens) or a custom color as lowercase #rrggbb; the empty string, or leaving it out, means follow the Quark. disabledNotifications lists the notification types (backup_due, backup_stale) the caller does not want, each at most once; because the body replaces the settings whole, leaving it out turns every type back on. A field the settings do not have, an unknown notification type and a repeated one are refused. Publishes no event: the change concerns only the caller.
// @Tags settings
// @Accept json
// @Produce json
// @Param body body usersettingsutil.Settings true "The settings"
// @Success 200 {object} usersettingsutil.Settings
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/me [put]
func updateMySettings(c *gin.Context) *serverutil.Response {
	userID, err := callerID(c)
	if err != nil {
		return serverutil.Unauthorized(err)
	}
	settings, err := usersettingsutil.Decode(http.MaxBytesReader(c.Writer, c.Request.Body, usersettingsutil.MaxRequestBytes))
	if err != nil {
		return serverutil.BadRequest(err)
	}
	queries, err := callerQueries(c)
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	result, err := usersettingsutil.Save(c.Request.Context(), usersettingsutil.SaveParams{
		Queries:  queries,
		UserID:   userID,
		Settings: settings,
	})
	if errors.Is(err, usersettingsutil.ErrInvalid) {
		return serverutil.BadRequest(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result.Settings)
}

var updateMySettingsRoute = serverutil.ApiRoute("PUT", "/settings/me", updateMySettings)
