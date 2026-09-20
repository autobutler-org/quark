package v0_ssh

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"

	"github.com/gin-gonic/gin"
)

func sshSystem(c *gin.Context) (sshutil.System, *serverutil.Response) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return sshutil.System{}, serverutil.InternalServerError(nil)
	}
	return deps.SSHSystem(), nil
}

// sshErrorResponse maps an sshutil error to its status code.
func sshErrorResponse(err error) *serverutil.Response {
	switch {
	case errors.Is(err, sshutil.ErrUnavailable), errors.Is(err, sshutil.ErrKeyExists):
		return serverutil.Conflict(err)
	case errors.Is(err, sshutil.ErrKeyNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, sshutil.ErrInvalidKey), errors.Is(err, sshutil.ErrPasswordTooShort), errors.Is(err, sshutil.ErrInvalidPassword):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}
