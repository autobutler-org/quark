package v0_chat

import (
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// requestContext is what every chat handler reads first: the dependencies,
// who the request acts as, and the channel id in the URL when there is one.
func requestContext(c *gin.Context) (deputil.Dependencies, accessutil.Principal, *serverutil.Response) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return deps, accessutil.Principal{}, serverutil.InternalServerError(nil)
	}
	if deps.Database() == nil {
		return deps, accessutil.Principal{}, serverutil.InternalServerError(errors.New("database unavailable"))
	}
	principal, _ := ctxutil.Get[accessutil.Principal](c, "principal")
	return deps, principal, nil
}

// callerContext is requestContext for a route that acts on the caller's own
// account, which needs one.
func callerContext(c *gin.Context) (deputil.Dependencies, accessutil.Principal, *serverutil.Response) {
	deps, principal, failed := requestContext(c)
	if failed == nil && principal.UserID == 0 {
		failed = serverutil.Unauthorized(errors.New("not authenticated"))
	}
	return deps, principal, failed
}

// channelID reads the :id path parameter. One that isn't a positive integer
// names no channel.
func channelID(c *gin.Context) (int64, *serverutil.Response) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		return 0, serverutil.NotFound(chatutil.ErrChannelNotFound)
	}
	return id, nil
}

// chatError maps an error from chatutil to its status code. The sentinels'
// text is written for the app to show, so it goes out unwrapped.
func chatError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, chatutil.ErrChannelNotFound), errors.Is(err, chatutil.ErrMemberNotFound),
		errors.Is(err, accessutil.ErrPrincipalNotFound), errors.Is(err, chatutil.ErrKeysNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, chatutil.ErrForbidden):
		return serverutil.Forbidden(err)
	case errors.Is(err, chatutil.ErrNameTaken):
		return serverutil.Conflict(err)
	case errors.Is(err, chatutil.ErrInvalidName), errors.Is(err, chatutil.ErrInvalidTopic),
		errors.Is(err, chatutil.ErrDefaultChannel), errors.Is(err, chatutil.ErrDefaultEveryone),
		errors.Is(err, accessutil.ErrGrantTarget), errors.Is(err, accessutil.ErrInvalidLevel),
		errors.Is(err, chatutil.ErrInvalidKeys):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}
