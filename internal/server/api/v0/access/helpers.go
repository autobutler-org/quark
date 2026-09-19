package v0_access

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// grantError maps an error from an accessutil grant call to its status code.
// The sentinels' text is written for the app to show, so it goes out unwrapped.
func grantError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, accessutil.ErrShareNotFound), errors.Is(err, accessutil.ErrGrantNotFound),
		errors.Is(err, accessutil.ErrPrincipalNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, accessutil.ErrShareForbidden):
		return serverutil.Forbidden(err)
	case errors.Is(err, accessutil.ErrInheritedGrant):
		return serverutil.Conflict(err)
	case errors.Is(err, accessutil.ErrTrashShare), errors.Is(err, accessutil.ErrSelfOwner),
		errors.Is(err, accessutil.ErrGrantTarget), errors.Is(err, accessutil.ErrInvalidLevel):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}
