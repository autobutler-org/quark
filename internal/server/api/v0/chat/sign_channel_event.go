package v0_chat

import (
	"net/http"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// signChannelEvent godoc
// @Summary Sign a chat channel event the caller made
// @Description Stores the caller's 64-byte Ed25519 signature, base64, over an event's canonical bytes, with the caller's published signing key beside it. Only the event's actor may sign it, and only once. The channel's members hear chat_channel_changed, so they can show it as verified.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param eventId path int true "Event id"
// @Param body body signEventBody true "The signature"
// @Success 200 {object} chatutil.ChannelEvent
// @Failure 400 {object} serverutil.Response "a signature of the wrong size"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel or event, the caller isn't a member, or isn't the event's actor"
// @Failure 409 {object} serverutil.Response "the event is already signed"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/events/{eventId}/signature [put]
func signChannelEvent(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	eventID, err := strconv.ParseInt(c.Param("eventId"), 10, 64)
	if err != nil || eventID <= 0 {
		return serverutil.NotFound(chatutil.ErrEventNotFound)
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxKeysRequestBytes)
	var body signEventBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidGrant)
	}
	result, err := chatutil.SignEvent(chatutil.SignEventParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal, ChannelID: id, EventID: eventID, Signature: body.Signature,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Event)
}

var signChannelEventRoute = serverutil.ApiRoute("PUT", "/chat/channels/:id/events/:eventId/signature", signChannelEvent)
