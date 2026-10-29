package v0_feeds

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/feedutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// deleteFeed godoc
// @Summary Unsubscribe from a feed
// @Description Deletes one of the caller's subscriptions and the entries stored for it. Another account's id, or one that names nothing, is a 404, for an admin too, and deletes nothing. Publishes feed_changed with the subscription's id to the caller's sessions.
// @Tags feeds
// @Param id path int true "Subscription id"
// @Success 204
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "the caller has no subscription with that id"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /feeds/{id} [delete]
func deleteFeed(c *gin.Context) *serverutil.Response {
	deps, userID, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := feedID(c)
	if failed != nil {
		return failed
	}
	if _, err := feedutil.Delete(feedutil.DeleteParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		UserID:  userID,
		ID:      id,
	}); err != nil {
		return feedError(err)
	}
	publish(deps, userID, id)
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var deleteFeedRoute = serverutil.ApiRoute("DELETE", "/feeds/:id", deleteFeed)
