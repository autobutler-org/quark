package v0_feeds

import (
	"github.com/autobutler-org/quark/pkg/util/feedutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getFeed godoc
// @Summary Get one of the caller's feed subscriptions
// @Description Returns one subscription of the caller's. Another account's id, or one that names nothing, is a 404, for an admin too.
// @Tags feeds
// @Produce json
// @Param id path int true "Subscription id"
// @Success 200 {object} feedutil.Feed
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "the caller has no subscription with that id"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /feeds/{id} [get]
func getFeed(c *gin.Context) *serverutil.Response {
	deps, userID, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := feedID(c)
	if failed != nil {
		return failed
	}
	result, err := feedutil.Get(feedutil.GetParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		UserID:  userID,
		ID:      id,
	})
	if err != nil {
		return feedError(err)
	}
	return serverutil.Ok().WithData(result.Feed)
}

var getFeedRoute = serverutil.ApiRoute("GET", "/feeds/:id", getFeed)
