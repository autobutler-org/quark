package v0_feeds

import (
	"github.com/autobutler-org/quark/pkg/util/feedutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// updateFeed godoc
// @Summary Rename a feed or file it in a folder
// @Description Changes the caller's label, the folder they file the subscription under, or both. A missing field is left as it is. An empty name clears the label, so the publisher's title shows, and an empty folder takes the feed out of its folder. Another account's id, or one that names nothing, is a 404, for an admin too, and changes nothing. The feed URL is not changed. Publishes feed_changed to the caller's sessions.
// @Tags feeds
// @Accept json
// @Produce json
// @Param id path int true "Subscription id"
// @Param body body updateRequest true "The label, the folder, or both"
// @Success 200 {object} feedutil.Feed
// @Failure 400 {object} serverutil.Response "a label that is not valid, or a body that changes nothing"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "the caller has no subscription with that id"
// @Failure 413 {object} serverutil.Response "a body over 16 KiB"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /feeds/{id} [patch]
func updateFeed(c *gin.Context) *serverutil.Response {
	deps, userID, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := feedID(c)
	if failed != nil {
		return failed
	}
	var body updateRequest
	if failed := bindBody(c, &body); failed != nil {
		return failed
	}
	result, err := feedutil.Update(feedutil.UpdateParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		UserID:  userID,
		ID:      id,
		Name:    body.Name,
		Folder:  body.Folder,
	})
	if err != nil {
		return feedError(err)
	}
	publish(deps, userID, result.Feed.ID)
	return serverutil.Ok().WithData(result.Feed)
}

var updateFeedRoute = serverutil.ApiRoute("PATCH", "/feeds/:id", updateFeed)
