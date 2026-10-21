package v0_files

import (
	"errors"
	"log/slog"
	"mime"
	"net/http"
	"path"
	"strconv"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/downloadutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// errNoAccess is what a caller hears about a path they may not see. It reads
// the same as a path that does not exist, because to them it does not.
var errNoAccess = errors.New("file not found")

// contentDisposition is the Content-Disposition header for a download named
// name. A request that authenticated with a download token is a browser saving
// the file, so it is always an attachment, with the name encoded per RFC 6266
// (#2226). Every other request keeps fallback: the video player and the
// in-app viewers rely on inline.
func contentDisposition(c *gin.Context, name, fallback string) string {
	if viaToken, _ := ctxutil.Get[bool](c, "downloadToken"); viaToken {
		return mime.FormatMediaType("attachment", map[string]string{"filename": name})
	}
	return fallback
}

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

func loadCaller(c *gin.Context) (deputil.Dependencies, accessutil.Access, *serverutil.Response) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return nil, accessutil.Access{}, serverutil.InternalServerError(nil)
	}
	access, resp := loadAccess(c, deps)
	if resp != nil {
		return nil, accessutil.Access{}, resp
	}
	return deps, access, nil
}

func loadAccess(c *gin.Context, deps deputil.Dependencies) (accessutil.Access, *serverutil.Response) {
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return accessutil.Access{}, serverutil.InternalServerError(err)
	}
	return access, nil
}

func gate(access accessutil.Access, serial, p string, level accessutil.Level) *serverutil.Response {
	check := access.Check(serial, p, level)
	if !check.Readable {
		return serverutil.NotFound(errNoAccess)
	}
	if !check.Allowed {
		return serverutil.Forbidden(errReadOnly)
	}
	return nil
}

func gateReadWrite(access accessutil.Access, serial, readPath, writePath string) *serverutil.Response {
	if !access.Check(serial, readPath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}
	if !access.Check(serial, writePath, accessutil.Write).Allowed {
		return serverutil.Forbidden(errReadOnly)
	}
	return nil
}

func writeExport(c *gin.Context, filePath, contentType, filename, stopped string, write func() error) *serverutil.Response {
	header := c.Writer.Header()
	header.Set("Content-Type", contentType)
	header.Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": filename}))
	err := write()
	if err == nil {
		return nil
	}
	if c.Writer.Written() {
		slog.Warn(stopped, "path", filePath, "err", err)
		return nil
	}
	header.Del("Content-Type")
	header.Del("Content-Disposition")
	return fileError(err)
}

func grantOwners(c *gin.Context, deps deputil.Dependencies, access accessutil.Access, serial string, written []uploadutil.UploadedFile) {
	for _, file := range written {
		if file.Created {
			accessutil.RecordOwner(c.Request.Context(), deps.Database(), access, serial, file.Path)
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
	var invalid *fileutil.InvalidRequestError
	if errors.As(err, &unsupported) || errors.As(err, &invalid) {
		return serverutil.BadRequest(err)
	}
	return serverutil.InternalServerError(err)
}

// decodeError answers a ?format=jpeg conversion whose image would not decode:
// 422 for one refused for its pixel count (#2762), 500 for anything else.
func decodeError(err error) *serverutil.Response {
	if errors.Is(err, photoutil.ErrImageTooLarge) {
		return serverutil.NewResponse().WithStatusCode(http.StatusUnprocessableEntity).WithError(err)
	}
	return serverutil.InternalServerError(err)
}

// zipError answers a folder download whose archive failed. Once any of the
// archive has been sent the status is committed, so the failure (usually the
// client going away) is only logged: answering 500 then made gin warn that
// the headers were already written and log the write error again. The request
// is marked "downloadInterrupted" so a download token survives it, and a
// retry starts the zip over instead of getting a 401 (#2270).
func zipError(c *gin.Context, p string, err error) *serverutil.Response {
	if c.Writer.Written() {
		slog.Warn("download: folder archive stopped partway", "path", p, "err", err)
		ctxutil.With(c, "downloadInterrupted", true)
		return nil
	}
	return serverutil.InternalServerError(err)
}

// acquireZipSlot takes one of the folder-zip slots (#2757) before any of the
// archive is written. When none frees up within the wait, or the client goes
// away first, it answers 503 with a Retry-After itself and reports false; the
// caller then writes nothing. On true the caller must call release once the
// zip ends, however it ends.
func acquireZipSlot(c *gin.Context, deps deputil.Dependencies, p string) (release func(), ok bool) {
	slots := deps.ZipSlots()
	release, ok = slots.Acquire(c.Request.Context())
	if !ok {
		slog.Warn("download: no folder zip slot free", "path", p, "cap", slots.Cap())
		c.Header("Retry-After", downloadutil.ZipRetryAfter)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "server busy, please retry"})
	}
	return release, ok
}

// uploadDestination is where an upload lands, for both the multipart endpoint
// and the chunked sessions: the files namespace of the device the request
// names (#1629, #2643).
func uploadDestination(deps deputil.Dependencies) uploadutil.Destination {
	return uploadutil.Destination{
		Registry: deps.VFSRegistry(),
		EventBus: deps.EventBus(),
	}
}

// beforeSave is the hook a save runs before it replaces a file: an automatic
// snapshot of an editor document's old content (#1173, #2992). Version history
// lives on the internal device only, so a save to a device addressed by
// serial gets no hook.
func beforeSave(c *gin.Context, deps deputil.Dependencies, serial string) func(path string) {
	fsys := uploadDestination(deps).FilesVFS("")
	if serial != "" || fsys == nil {
		return nil
	}
	return deps.FileVersions().BeforeSave(fileversionutil.BeforeSaveParams{
		Ctx: c.Request.Context(), FS: fsys, AuthorID: callerID(c),
	})
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
	case errors.Is(err, uploadutil.ErrSessionNotFound),
		errors.Is(err, uploadutil.ErrNoDestination):
		return serverutil.NotFound(err)
	case nameTaken(err):
		// Answered the way the multipart endpoint answers it. Unlike the offset
		// mismatch it carries no X-Upload-Offset, which is how a client tells
		// the two 409s apart.
		return serverutil.Conflict(err)
	case errors.Is(err, uploadutil.ErrInvalidRange),
		errors.Is(err, uploadutil.ErrInvalidRequest):
		return serverutil.BadRequest(err)
	case errors.Is(err, uploadutil.ErrTooManySessions):
		return serverutil.NewResponse().WithStatusCode(http.StatusTooManyRequests).WithError(err)
	default:
		return serverutil.InternalServerError(err)
	}
}

// nameTaken reports an upload refused because its name is in use and the
// caller chose neither overwrite nor keepBoth (#2016). It is a 409.
func nameTaken(err error) bool {
	return errors.Is(err, vfs.ErrConflict)
}

// errBothConflictChoices refuses an upload asking to overwrite and to keep
// both at once.
var errBothConflictChoices = errors.New("choose overwrite or keepBoth, not both")

// errNoDevice refuses an upload to a serial with no files namespace: a drive
// that is not attached.
var errNoDevice = errors.New("storage device not found")

// publishUpload announces the files an upload landed, so every open client
// sees them. Nothing is published when nothing was written — including a
// refused upload, which changed no file tree.
func publishUpload(deps deputil.Dependencies, serial, rootDir string, written []uploadutil.UploadedFile) {
	if len(written) == 0 {
		return
	}
	deps.EventBus().Publish(eventbus.Event{
		Kind:         eventbus.EventUpload,
		Path:         rootDir,
		DeviceSerial: serial,
	})
}

// uploadedPaths is the answer to an upload: where each file landed. The
// nested route's rootDir keeps gin's leading slash on the VFS branch, so it is
// trimmed to match the files-relative paths the photo and album APIs use.
func uploadedPaths(written []uploadutil.UploadedFile) uploadFilesResponse {
	paths := make([]string, 0, len(written))
	for _, file := range written {
		paths = append(paths, strings.TrimPrefix(file.Path, "/"))
	}
	return uploadFilesResponse{Paths: paths}
}

// importPresentation is the import route every presentation format shares:
// it checks read access on filePath and write access on rootDir (the file's
// own folder when left out), calls run, makes the caller the owner of what
// it wrote, and answers with the .qslide's path and warnings. Kind names the
// format in the log.
func importPresentation(c *gin.Context, kind string,
	run func(fileutil.ImportPptxParams) (fileutil.ImportPptxResult, error)) *serverutil.Response {
	filePath := c.Query("filePath")
	if filePath == "" {
		return serverutil.BadRequest(errors.New("filePath query parameter is required"))
	}
	rootDir, ok := c.GetQuery("rootDir")
	if !ok {
		rootDir = path.Dir(filePath)
	}
	if rootDir == "." {
		rootDir = ""
	}
	serial := c.Query("serial")

	deps, access, resp := loadCaller(c)
	if resp != nil {
		return resp
	}
	if resp := gateReadWrite(access, serial, filePath, rootDir); resp != nil {
		return resp
	}

	result, err := run(fileutil.ImportPptxParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		EventBus: deps.EventBus(),
		FilePath: filePath,
		RootDir:  rootDir,
		Serial:   serial,
	})
	if err != nil {
		// An import runs for as long as the package is large, and the access
		// log only carries the status code (#1705).
		slog.Error("import: presentation import failed", "kind", kind, "path", filePath, "err", err)
		return fileError(err)
	}
	accessutil.RecordOwner(c.Request.Context(), deps.Database(), access, serial, result.Path)
	if result.MediaDirCreated {
		accessutil.RecordOwner(c.Request.Context(), deps.Database(), access, serial, result.MediaDir)
	} else {
		for _, p := range result.Media {
			accessutil.RecordOwner(c.Request.Context(), deps.Database(), access, serial, p)
		}
	}

	warnings := make([]ImportWarningJSON, 0, len(result.Warnings))
	for _, w := range result.Warnings {
		warnings = append(warnings, ImportWarningJSON{Slide: w.Slide, Message: w.Message})
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(ImportPptxJSON{
		Path:     result.Path,
		MediaDir: result.MediaDir,
		Slides:   result.Slides,
		Pictures: result.Pictures,
		Warnings: warnings,
	})
}
