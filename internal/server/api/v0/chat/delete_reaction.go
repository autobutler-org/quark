package v0_chat

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// deleteReaction godoc
// @Summary Remove a reaction from a chat message
// @Description Deletes the reaction and tells the channel's readers with a chat_reaction_changed that carries no reaction. Removing your own needs add_reactions, and removing someone else's manage_reactions; either way the caller must hold read_messages now, and anyone without it gets 404, delegated managers and admins included.
// @Tags chat
// @Produce json
// @Param id path int true "Reaction id"
// @Success 200 {object} chatutil.Reaction
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "your own without add_reactions, or someone else's without manage_reactions"
// @Failure 404 {object} serverutil.Response "no such reaction, or the caller lacks read_messages in its channel"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/reactions/{id} [delete]
func deleteReaction(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		return serverutil.NotFound(chatutil.ErrReactionNotFound)
	}
	result, err := chatutil.RemoveReaction(chatutil.RemoveReactionParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal, ReactionID: id,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Reaction)
}

var deleteReactionRoute = serverutil.ApiRoute("DELETE", "/chat/reactions/:id", deleteReaction)
