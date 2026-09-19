package v0_admin

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// accountErrorResponse maps an error from an authutil account action to its
// status code. The sentinels' text is written for the app to show, so it goes
// out unwrapped.
func accountErrorResponse(err error) *serverutil.Response {
	switch {
	case errors.Is(err, authutil.ErrUserNotFound), errors.Is(err, authutil.ErrRequestNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, authutil.ErrLastAdmin), errors.Is(err, authutil.ErrUsernameTaken), errors.Is(err, authutil.ErrFolderExists):
		return serverutil.Conflict(err)
	case errors.Is(err, authutil.ErrInvalidUsername), errors.Is(err, authutil.ErrPasswordTooShort), errors.Is(err, authutil.ErrSelfAction):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}
