package v0_feeds

import (
	"github.com/autobutler-org/quark/pkg/util/feedutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listFeeds godoc
// @Summary List the caller's feed subscriptions
// @Description Returns the caller's subscriptions, folders first, then by the caller's name or the publisher's title. Another account's subscriptions are not included. An account with none gets an empty list.
// @Tags feeds
// @Produce json
// @Success 200 {array} feedutil.Feed
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /feeds [get]
func listFeeds(c *gin.Context) *serverutil.Response {
	deps, userID, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	result, err := feedutil.List(feedutil.ListParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		UserID:  userID,
	})
	if err != nil {
		return feedError(err)
	}
	return serverutil.Ok().WithData(result.Feeds)
}

var listFeedsRoute = serverutil.ApiRoute("GET", "/feeds", listFeeds)
