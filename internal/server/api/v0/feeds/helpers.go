package v0_feeds

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/feedutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// errBadRequest is the 400 a malformed body gets. The bind error is not
// returned: it can quote the body, and the body holds the feed URL.
var errBadRequest = errors.New("the request is not valid")

// errBodyTooLarge is the 413 a body over its limit gets.
var errBodyTooLarge = errors.New("request body is too large")

const maxBodyBytes = 16 << 10

// callerContext is what every feeds handler reads first: the dependencies,
// and the signed-in account the request acts on.
func callerContext(c *gin.Context) (deputil.Dependencies, int64, *serverutil.Response) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return deps, 0, serverutil.InternalServerError(errors.New("database unavailable"))
	}
	principal, _ := ctxutil.Get[accessutil.Principal](c, "principal")
	if principal.UserID == 0 {
		return deps, 0, serverutil.Unauthorized(errors.New("not authenticated"))
	}
	return deps, principal.UserID, nil
}

// feedID reads the :id path parameter. One that isn't a positive integer
// names no subscription.
func feedID(c *gin.Context) (int64, *serverutil.Response) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		return 0, serverutil.NotFound(feedutil.ErrNotFound)
	}
	return id, nil
}

// bindBody decodes a JSON body of at most maxBodyBytes into out. A body over
// the limit is a 413. Any other malformed body is a 400 that does not quote it.
func bindBody(c *gin.Context, out any) *serverutil.Response {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBodyBytes)
	err := c.ShouldBindJSON(out)
	if _, tooLarge := errors.AsType[*http.MaxBytesError](err); tooLarge {
		return serverutil.NewResponse().WithStatusCode(http.StatusRequestEntityTooLarge).WithError(errBodyTooLarge)
	}
	if err != nil {
		return serverutil.BadRequest(errBadRequest)
	}
	return nil
}

// feedError maps a feedutil error onto its status. Anything else becomes a
// fixed sentence, so a database detail that repeats a feed URL is not sent.
func feedError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, feedutil.ErrInvalidURL),
		errors.Is(err, feedutil.ErrForbiddenAddress),
		errors.Is(err, feedutil.ErrUnresolved),
		errors.Is(err, feedutil.ErrFetchFailed),
		errors.Is(err, feedutil.ErrNoFeed),
		errors.Is(err, feedutil.ErrInvalidLabel),
		errors.Is(err, feedutil.ErrLabelTooLong),
		errors.Is(err, feedutil.ErrNoChange):
		return serverutil.BadRequest(err)
	case errors.Is(err, feedutil.ErrAlreadySubscribed):
		return serverutil.Conflict(err)
	case errors.Is(err, feedutil.ErrNotFound):
		return serverutil.NotFound(err)
	default:
		return serverutil.InternalServerError(feedutil.ErrStoreFailed)
	}
}

func publish(deps deputil.Dependencies, userID, feedID int64) {
	feedutil.PublishChanged(feedutil.PublishChangedParams{EventBus: deps.EventBus(), UserID: userID, FeedID: feedID})
}
