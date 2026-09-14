package v0_videos

import (
	"errors"
	"fmt"
	"log/slog"
	"math"
	"path"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// errNoAccess is what a caller hears about a video they may not see. It reads
// the same as a video that does not exist, because to them it does not.
var errNoAccess = errors.New("video not found")

// errReadOnly is what a caller hears when they may see a video but not write
// beside it.
var errReadOnly = errors.New("you do not have permission to change this")

// grantOwner records the caller as owner of a file an edit just wrote (#1904).
// The file already exists by then, so a failure is logged rather than failing
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

// checkEdit applies the access an edit that writes a new file beside a video
// needs: read on the video (404 without it) and write on its folder (403).
func checkEdit(access accessutil.Access, serial, relPath string) *serverutil.Response {
	if !access.Check(serial, relPath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}
	if !access.Check(serial, path.Dir(accessutil.Canonical(relPath)), accessutil.Write).Allowed {
		return serverutil.Forbidden(errReadOnly)
	}
	return nil
}

// formatFrameTimestamp converts a Duration to a human-readable frame label,
// e.g. 2500ms → "0m02s", 3725000ms → "1h02m05s".
func formatFrameTimestamp(d time.Duration) string {
	h := int(d.Hours())
	m := int(d.Minutes()) % 60
	s := int(d.Seconds()) % 60
	if h > 0 {
		return fmt.Sprintf("%dh%02dm%02ds", h, m, s)
	}
	return fmt.Sprintf("%dm%02ds", m, s)
}

func roundTo(v float64, decimals int) float64 {
	factor := math.Pow(10, float64(decimals))
	return math.Round(v*factor) / factor
}
