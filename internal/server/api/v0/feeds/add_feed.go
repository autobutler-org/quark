package v0_feeds

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/feedutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// addFeed godoc
// @Summary Subscribe to a feed
// @Description Subscribes the caller to a feed. Without discover, url is the feed address and nothing is fetched. With discover, url is a site page: it is fetched and searched for a feed link. One link is subscribed to. Several links return 409 and the candidates, and store nothing; the caller subscribes to the chosen candidate with discover left false. The address must be http or https and must not resolve to a private, loopback or link-local range. A feed address can carry a private token, and no error repeats it. name is the caller's label and folder is the one folder they file it under. Publishes feed_changed to the caller's sessions.
// @Tags feeds
// @Accept json
// @Produce json
// @Param body body addRequest true "The feed or site address"
// @Success 201 {object} feedutil.Feed
// @Failure 400 {object} serverutil.Response "an address that is not allowed, a page with no feed, or a malformed body"
// @Failure 401 {object} serverutil.Response
// @Failure 409 {object} ChoiceJSON "the caller already subscribes to that feed, or the page offers several"
// @Failure 413 {object} serverutil.Response "a body over 16 KiB"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /feeds [post]
func addFeed(c *gin.Context) *serverutil.Response {
	deps, userID, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	var body addRequest
	if failed := bindBody(c, &body); failed != nil {
		return failed
	}
	result, err := feedutil.Add(feedutil.AddParams{
		Ctx:      c.Request.Context(),
		Queries:  deps.Database().Queries,
		UserID:   userID,
		URL:      body.URL,
		Name:     body.Name,
		Folder:   body.Folder,
		Discover: body.Discover,
	})
	if errors.Is(err, feedutil.ErrSeveralFeeds) {
		return serverutil.NewResponse().WithStatusCode(http.StatusConflict).WithData(ChoiceJSON{
			Error:      feedutil.ErrSeveralFeeds.Error(),
			Candidates: result.Candidates,
		})
	}
	if err != nil {
		return feedError(err)
	}
	publish(deps, userID, result.Feed.ID)
	return serverutil.NewResponse().WithStatusCode(http.StatusCreated).WithData(result.Feed)
}

var addFeedRoute = serverutil.ApiRoute("POST", "/feeds", addFeed)
