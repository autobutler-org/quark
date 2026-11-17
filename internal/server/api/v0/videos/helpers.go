package v0_videos

import (
	"errors"
	"fmt"
	"math"
	"net/http"
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

// errUnreadableVideo is what a caller hears about a file that is there but
// does not read as a video: damaged, or in a container sprocket does not
// parse. sprocket's own reason follows it in the error for the logs.
var errUnreadableVideo = errors.New("can't read this video: it may be damaged or in a format the device doesn't read")

// errReadOnly is what a caller hears when they may see a video but not write
// beside it.
var errReadOnly = errors.New("you do not have permission to change this")

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

// openError is the response to a video that could not be opened or read:
// 404 for a missing file or a folder, and 422 for a file that does not read as
// a video (#3417).
func openError(err error, relPath string) *serverutil.Response {
	switch {
	case errors.Is(err, vfs.ErrPermissionDenied):
		return serverutil.BadRequest(errInvalidPath)
	case errors.Is(err, vfs.ErrNotFound), errors.Is(err, vfs.ErrIsDirectory):
		return serverutil.NotFound(fmt.Errorf("video not found: %s", relPath))
	case errors.Is(err, videoutil.ErrNotAVideo):
		return refuseVideo(fmt.Errorf("%w: %w", errUnreadableVideo, err))
	}
	return serverutil.InternalServerError(err)
}

// refuseVideo is the 422 for err, a video that is there but can't be read or
// cut. Its body carries the cause as videoutil.ReasonOf names it, so every
// route says the same thing about the same file (#3423).
func refuseVideo(err error) *serverutil.Response {
	return serverutil.NewResponse().WithStatusCode(http.StatusUnprocessableEntity).
		WithData(videoRefusalJSON{Error: err.Error(), Reason: videoutil.ReasonOf(err)})
}

// filesVFS is the files namespace of the device with serial, the internal
// drive for the empty one, or nil when no such device is attached.
func filesVFS(deps deputil.Dependencies, serial string) vfs.VFS {
	fsys, err := vfs.FilesFS(deps.VFSRegistry(), serial)
	if err != nil {
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
