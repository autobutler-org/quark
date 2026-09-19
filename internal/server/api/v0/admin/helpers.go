package v0_admin

import (
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// accountErrorResponse maps an error from an authutil account action to its
// status code. The sentinels' text is written for the app to show, so it goes
// out unwrapped.
func accountErrorResponse(err error) *serverutil.Response {
	switch {
	case errors.Is(err, authutil.ErrUserNotFound), errors.Is(err, authutil.ErrRequestNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, authutil.ErrLastAdmin), errors.Is(err, authutil.ErrUsernameTaken):
		return serverutil.Conflict(err)
	case errors.Is(err, authutil.ErrInvalidUsername), errors.Is(err, authutil.ErrPasswordTooShort), errors.Is(err, authutil.ErrSelfAction):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}

// groupErrorResponse maps an error from a grouputil action to its status code.
// Like the account sentinels, the group sentinels go out unwrapped.
func groupErrorResponse(err error) *serverutil.Response {
	switch {
	case errors.Is(err, grouputil.ErrGroupNotFound), errors.Is(err, grouputil.ErrNotMember), errors.Is(err, authutil.ErrUserNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, grouputil.ErrGroupNameTaken), errors.Is(err, grouputil.ErrGroupFolderTaken):
		return serverutil.Conflict(err)
	case errors.Is(err, grouputil.ErrInvalidGroupName), errors.Is(err, grouputil.ErrBuiltinGroup):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}

// idParam reads a numeric id from the URL. One that is not a number names
// nothing, so it is notFound.
func idParam(c *gin.Context, name string, notFound error) (int64, error) {
	id, err := strconv.ParseInt(c.Param(name), 10, 64)
	if err != nil {
		return 0, notFound
	}
	return id, nil
}
