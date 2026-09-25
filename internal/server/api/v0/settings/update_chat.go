package v0_settings

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// updateChat godoc
// @Summary Turn the chat beta on or off
// @Description Sets whether chat is available. Chat is on until an admin turns it off; while off every /chat route answers 404, and nothing stored is deleted. Admin-only.
// @Tags settings
// @Accept json
// @Produce json
// @Param body body chatSetting true "Whether chat is on"
// @Success 200 {object} chatSetting
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/chat [put]
func updateChat(c *gin.Context) *serverutil.Response {
	var body chatSetting
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	if err := settingsutil.SetChatEnabled(*body.Enabled); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(body)
}

var updateChatRoute = serverutil.ApiRoute("PUT", "/settings/chat", updateChat)
