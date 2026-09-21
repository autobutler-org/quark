package v0_files

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// errNoAccess is what a caller hears about a path they may not see. It reads
// the same as a path that does not exist, because to them it does not.
var errNoAccess = errors.New("file not found")

// errReadOnly is what a caller hears when they may see a path but not change
// it.
var errReadOnly = errors.New("you do not have permission to change this")

// errHomeFolder is what a member hears when they try to delete or move a
// home folder itself.
var errHomeFolder = errors.New("a home folder can't be deleted or moved")

// errGroupFolder is what a member hears when they try to delete or move a
// group's folder itself.
var errGroupFolder = errors.New("a group's folder can't be deleted or moved")

// refuseHomeRoot answers a non-admin's delete or move of a home folder or a
// group folder itself (#2016): 404 if they may not see it, 403 if they may.
// It returns nil for anything else, including every path inside one. Admins
// pass, as they do every other access check.
func refuseHomeRoot(access accessutil.Access, serial, p string) *serverutil.Response {
	if access.Principal().IsAdmin {
		return nil
	}
	var refusal error
	switch {
	case accessutil.IsHomeRoot(serial, p):
		refusal = errHomeFolder
	case accessutil.IsGroupRoot(serial, p):
		refusal = errGroupFolder
	default:
		return nil
	}
	if !access.Check(serial, p, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}
	return serverutil.Forbidden(refusal)
}

// grantOwner records the caller as owner of something they just created
// (#1903). The item already exists by then, so a failure is logged rather than
// failing the request: the caller still reaches it through the write grant
// that let them create it.
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

// grantOwners records the caller as owner of every file an upload created. A
// file the upload replaced keeps the rows it had (#1903).
func grantOwners(c *gin.Context, deps deputil.Dependencies, access accessutil.Access, serial string, written []storageutil.UploadedFile) {
	for _, file := range written {
		if file.Created {
			grantOwner(c, deps, access, serial, file.Path)
		}
	}
}

// callerID is the signed-in user an upload session belongs to. A request with
// no principal is user 0, and the routes that open sessions refuse it first.
func callerID(c *gin.Context) int64 {
	principal, _ := ctxutil.Get[accessutil.Principal](c, "principal")
	return principal.UserID
}

// fileError maps what fileutil reports onto the status codes the client
// contract is written against. A path none of the sources could produce is the
// only failure that is not the server's fault; the message travels unchanged
// either way, so the client keeps reading the same sentences it always has.
func fileError(err error) *serverutil.Response {
	var notFound *fileutil.NotFoundError
	if errors.As(err, &notFound) {
		return serverutil.NotFound(err)
	}
	var unsupported *fileutil.UnsupportedError
	if errors.As(err, &unsupported) {
		return serverutil.BadRequest(err)
	}
	return serverutil.InternalServerError(err)
}

// downloadFileVFS handles file downloads via the VFS layer.
// RAW files (needing OS path for dcraw/LibRaw) are excluded before calling this.
func downloadFileVFS(c *gin.Context, deps deputil.Dependencies, fsys vfs.VFS, access accessutil.Access, filePath string, wantsJPEG bool) *serverutil.Response {
	ctx := c.Request.Context()

	opened, err := fileutil.OpenVFSDownload(fileutil.OpenVFSDownloadParams{
		Ctx:       ctx,
		FS:        fsys,
		FilePath:  filePath,
		WantsJPEG: wantsJPEG,
	})
	if err != nil {
		return fileError(err)
	}

	switch opened.Kind {
	case fileutil.DownloadFolder:
		// Zip and stream the directory contents.
		c.Writer.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", opened.FileName))
		c.Writer.Header().Set("Content-Type", "application/octet-stream")
		if err := fileutil.ZipVFSDir(ctx, fsys, filePath, strings.TrimSuffix(opened.FileName, ".zip"), access, c.Writer); err != nil {
			return serverutil.InternalServerError(err)
		}
		return nil

	case fileutil.DownloadJPEG:
		// Acquire IO semaphore for JPEG conversion.
		if sem := deps.IOSemaphore(); sem != nil {
			if !sem.AcquireDefault(ctx) {
				slog.Warn("download: IO semaphore timed out for VFS JPEG conversion",
					"path", filePath,
					"available", sem.Available(),
					"cap", sem.Cap(),
				)
				c.Header("Retry-After", "5")
				c.JSON(http.StatusServiceUnavailable, gin.H{"error": "server busy, please retry"})
				return nil
			}
			defer sem.Release()
		}

		r, err := fsys.Open(ctx, filePath)
		if err != nil {
			return serverutil.NotFound(err)
		}
		defer r.Close()

		img, err := fileutil.DecodeImage(r)
		if err != nil {
			return serverutil.InternalServerError(err)
		}

		c.Header("Content-Disposition", fmt.Sprintf("inline; filename=%s", opened.FileName))
		c.Header("Content-Type", opened.ContentType)
		c.Status(http.StatusOK)
		if err := fileutil.EncodeJPEG(c.Writer, img); err != nil {
			slog.Error("download: VFS JPEG stream encode failed", "path", filePath, "err", err)
		}
		return nil
	}

	r, err := fsys.Open(ctx, filePath)
	if err != nil {
		return serverutil.NotFound(err)
	}
	defer r.Close()

	c.Header("Content-Disposition", fmt.Sprintf("inline; filename=%s", opened.FileName))
	c.Header("Content-Type", opened.ContentType)

	// If the underlying VFS returns an io.ReadSeeker (e.g. *os.File from LocalVFS
	// or StorageServiceVFS), use http.ServeContent so the response honours HTTP
	// range requests (RFC 7233) — required for video seeking and resumable
	// downloads. Falls back to sequential streaming via DataFromReader otherwise.
	if rs, ok := r.(io.ReadSeeker); ok {
		http.ServeContent(c.Writer, c.Request, opened.Info.Name, opened.Info.ModTime, rs)
		return nil
	}

	c.DataFromReader(http.StatusOK, opened.Info.Size, opened.ContentType, r, nil)
	return nil
}

// uploadDestination is where an upload lands, for both this endpoint and the
// chunked sessions in upload_session.go. Both have to make the same choice
// between the VFS namespace and the StorageService, so the choice lives in one
// place (#1629).
func uploadDestination(deps deputil.Dependencies) uploadutil.Destination {
	return uploadutil.Destination{
		Registry: deps.VFSRegistry(),
		Storage:  deps.StorageService(),
		EventBus: deps.EventBus(),
	}
}

// Resumable chunked uploads (#1629). A large file no longer rides on one
// request that a dropped connection costs in full: the client opens a session,
// PUTs the bytes a chunk at a time, and after an interruption asks what landed
// and carries on from there. Small files still take the multipart endpoint in
// upload_files.go, where chunking would be pure overhead.
const (
	// uploadOffsetHeader carries the committed offset back with a 409, so a
	// client that guessed wrong resyncs without a second round trip.
	uploadOffsetHeader = "X-Upload-Offset"
	// sessionIDParam is the path parameter naming the session.
	sessionIDParam = "sessionId"
)

// uploadSessionError maps what uploadutil reports onto the status codes the
// client contract is written against. The offset mismatch is the only one that
// carries state back in a header: everything the client needs to resync from a
// 409 is in the response it already has.
func uploadSessionError(c *gin.Context, err error) *serverutil.Response {
	var mismatch *uploadutil.OffsetMismatchError
	switch {
	case errors.As(err, &mismatch):
		c.Header(uploadOffsetHeader, strconv.FormatInt(mismatch.Offset, 10))
		return serverutil.Conflict(err)
	case errors.Is(err, uploadutil.ErrSessionNotFound):
		return serverutil.NotFound(err)
	case nameTaken(err):
		// Answered the way the multipart endpoint answers it. Unlike the offset
		// mismatch it carries no X-Upload-Offset, which is how a client tells
		// the two 409s apart.
		return serverutil.Conflict(err)
	case errors.Is(err, uploadutil.ErrInvalidRange),
		errors.Is(err, uploadutil.ErrInvalidRequest):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}

// nameTaken reports an upload refused because its name is in use and the
// caller chose neither overwrite nor keepBoth (#2016). The VFS reports it as
// vfs.ErrConflict and the StorageService as fs.ErrExist; both are a 409.
func nameTaken(err error) bool {
	return errors.Is(err, vfs.ErrConflict) || errors.Is(err, fs.ErrExist)
}

// errBothConflictChoices refuses an upload asking to overwrite and to keep
// both at once.
var errBothConflictChoices = errors.New("choose overwrite or keepBoth, not both")

// publishUpload announces the files an upload landed, so every open client
// sees them. Nothing is published when nothing was written — including a
// refused upload, which changed no file tree.
func publishUpload(deps deputil.Dependencies, rootDir string, written []storageutil.UploadedFile) {
	if len(written) == 0 {
		return
	}
	deps.EventBus().Publish(eventbus.Event{
		Kind: eventbus.EventUpload,
		Path: rootDir,
	})
}
