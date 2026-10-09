package v0_videos

import (
	"errors"
	"fmt"
	"log/slog"
	"math"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// errNoAccess is what a caller hears about a video they may not see. It reads
// the same as a video that does not exist, because to them it does not.
var errNoAccess = errors.New("video not found")

// errInvalidPath answers a relPath that cannot name a video: the device root,
// or a path that escapes it.
var errInvalidPath = errors.New("invalid relPath")

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

// openVideo opens the video at relPath on the device with serial through that
// device's files namespace (#2639), and answers the request itself when it
// cannot: 404 for a device that is not attached, a missing file or a folder,
// 400 for the device root or a path escaping it. The caller closes the video.
func openVideo(c *gin.Context, deps deputil.Dependencies, serial, relPath string) (videoutil.Source, *serverutil.Response) {
	fsys := filesVFS(deps, serial)
	if fsys == nil {
		return videoutil.Source{}, serverutil.NotFound(fmt.Errorf("video not found: %s", relPath))
	}
	if isRoot(relPath) {
		return videoutil.Source{}, serverutil.BadRequest(errInvalidPath)
	}
	video, err := videoutil.OpenSource(c.Request.Context(), videoutil.OpenSourceParams{FS: fsys, Path: relPath})
	if err != nil {
		return videoutil.Source{}, openError(err, relPath)
	}
	return video, nil
}

// openError is the response to a video that could not be opened or read.
func openError(err error, relPath string) *serverutil.Response {
	switch {
	case errors.Is(err, vfs.ErrPermissionDenied):
		return serverutil.BadRequest(errInvalidPath)
	case errors.Is(err, vfs.ErrNotFound), errors.Is(err, vfs.ErrIsDirectory), errors.Is(err, videoutil.ErrNotAVideo):
		return serverutil.NotFound(fmt.Errorf("video not found or not readable: %s", relPath))
	}
	return serverutil.InternalServerError(err)
}

// filesVFS is the files namespace of the device with serial, the internal
// drive for the empty one, or nil when no such device is attached.
func filesVFS(deps deputil.Dependencies, serial string) vfs.VFS {
	registry := deps.VFSRegistry()
	if registry == nil {
		return nil
	}
	fsys, ok := registry.Get(vfs.FilesNamespace(serial))
	if !ok {
		return nil
	}
	return fsys
}

// isRoot reports whether relPath names the device root, which is never a
// video.
func isRoot(relPath string) bool {
	return path.Clean("/"+relPath) == "/"
}

func roundTo(v float64, decimals int) float64 {
	factor := math.Pow(10, float64(decimals))
	return math.Round(v*factor) / factor
}
