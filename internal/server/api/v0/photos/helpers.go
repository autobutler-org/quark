package v0_photos

import (
	"errors"
	"log/slog"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/gin-gonic/gin"
)

// errNoAccess is what a caller hears about a photo they may not see. It reads
// the same as a photo that does not exist, because to them it does not.
var errNoAccess = errors.New("photo not found")

// errReadOnly is what a caller hears when they may see a photo but not change
// it or write beside it.
var errReadOnly = errors.New("you do not have permission to change this")

// grantOwner records the caller as owner of a copy they just wrote (#1904).
// The copy already exists by then, so a failure is logged rather than failing
// the request: the caller still reaches it through the write grant that let
// them create it.
func grantOwner(c *gin.Context, deps deputil.Dependencies, access accessutil.Access, serial, p string) {
	if _, err := accessutil.GrantOwnerIfNeeded(accessutil.GrantOwnerIfNeededParams{
		Ctx:          c.Request.Context(),
		Database:     deps.Database(),
		Access:       access,
		DeviceSerial: serial,
		Path:         p,
	}); err != nil {
		slog.Error("access: could not record the owner of a new item", "path", p, "serial", serial, "err", err)
	}
}
