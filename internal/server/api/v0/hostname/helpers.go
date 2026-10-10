package v0_hostname

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/hostnameutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// maxBodyBytes bounds the rename body, which holds one short name.
const maxBodyBytes = 1024

// hostnameErrorResponse maps a hostnameutil error to its status code.
func hostnameErrorResponse(err error) *serverutil.Response {
	switch {
	case errors.Is(err, hostnameutil.ErrInvalidHostname):
		return serverutil.BadRequest(err)
	case errors.Is(err, hostnameutil.ErrUnavailable):
		return serverutil.Conflict(err)
	default:
		return serverutil.InternalServerError(err)
	}
}
