package v0_files

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"

	"github.com/gin-gonic/gin"
)

// uploadFiles godoc
// @Summary Upload files to the top-level directory
// @Description Upload one or more files via multipart/form-data. Needs write access on the top-level directory; the caller owns each file the upload creates. A name already in use is a 409 unless overwrite or keepBoth says what to do about it. Overwriting a .qslide, .qsheet or .qdoc on the internal device first snapshots its old content into its version history. Answers with the files-relative path each file landed at, after any keepBoth rename. A photo or video's client-rendered thumbnail (JPEG, long edge 400) may follow its file as a part named thumbnail whose filename is the file's; one that names no earlier file, or is not a valid JPEG, is skipped. A request with no part named files is a 400. A batch that stops partway, cut off (400) or on a taken name (409), lands the files before the failure, and its error body lists them under landed, so a retry resends only the rest.
// @Tags files
// @Accept multipart/form-data
// @Produce json
// @Param serial query string false "Device serial number to upload to"
// @Param overwrite query boolean false "Replace a file of the same name"
// @Param keepBoth query boolean false "Land under the first free name, e.g. file_(1).txt, when the name is taken"
// @Param files formData []file true "One file per part; repeat the part to upload more than one" collectionFormat(multi)
// @Param thumbnail formData file false "Thumbnail JPEG for the file of the same filename sent before it"
// @Success 200 {object} uploadFilesResponse "OK"
// @Failure 400 {object} uploadFailedResponse "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} uploadFailedResponse "Not Found"
// @Failure 409 {object} uploadFailedResponse "Conflict"
// @Failure 500 {object} uploadFailedResponse "Internal Server Error"
// @Security BearerAuth
// @Router /files/upload [post]
func uploadFiles(c *gin.Context) *serverutil.Response {
	return uploadFilesNested(c, "")
}

// uploadFiles godoc
// @Summary Upload files to a nested directory
// @Description Upload one or more files via multipart/form-data. Needs write access on the directory; the caller owns each file the upload creates. A name already in use is a 409 unless overwrite or keepBoth says what to do about it. Overwriting a .qslide, .qsheet or .qdoc on the internal device first snapshots its old content into its version history. Answers with the files-relative path each file landed at, after any keepBoth rename. A photo or video's client-rendered thumbnail (JPEG, long edge 400) may follow its file as a part named thumbnail whose filename is the file's; one that names no earlier file, or is not a valid JPEG, is skipped. A request with no part named files is a 400. A batch that stops partway, cut off (400) or on a taken name (409), lands the files before the failure, and its error body lists them under landed, so a retry resends only the rest.
// @Tags files
// @Accept multipart/form-data
// @Produce json
// @Param rootDir path string true "Directory to upload into"
// @Param serial query string false "Device serial number to upload to"
// @Param overwrite query boolean false "Replace a file of the same name"
// @Param keepBoth query boolean false "Land under the first free name, e.g. file_(1).txt, when the name is taken"
// @Param files formData []file true "One file per part; repeat the part to upload more than one" collectionFormat(multi)
// @Param thumbnail formData file false "Thumbnail JPEG for the file of the same filename sent before it"
// @Success 200 {object} uploadFilesResponse "OK"
// @Failure 400 {object} uploadFailedResponse "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} uploadFailedResponse "Not Found"
// @Failure 409 {object} uploadFailedResponse "Conflict"
// @Failure 500 {object} uploadFailedResponse "Internal Server Error"
// @Security BearerAuth
// @Router /files/upload/{rootDir} [post]
func uploadFilesNested(c *gin.Context, rootDir string) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	serial := c.Query("serial")
	overwrite := c.Query("overwrite") == "true"
	keepBoth := c.Query("keepBoth") == "true"
	if overwrite && keepBoth {
		return serverutil.BadRequest(errBothConflictChoices)
	}
	// Checked before a byte of the body is read.
	access, resp := loadAccess(c, deps)
	if resp != nil {
		return resp
	}
	if resp := gate(access, serial, rootDir, accessutil.Write); resp != nil {
		return resp
	}
	reader, err := c.Request.MultipartReader()
	if err != nil {
		return serverutil.BadRequest(err)
	}
	// Every device's files are a namespace of their own; a serial with none is
	// not a device to upload to (#2643).
	fsys := uploadDestination(deps).FilesVFS(serial)
	if fsys == nil {
		return serverutil.NotFound(errNoDevice)
	}
	written, err := uploadutil.WriteMultipartVFS(uploadutil.WriteMultipartParams{
		Ctx:       c.Request.Context(),
		FS:        fsys,
		Reader:    reader,
		RootDir:   rootDir,
		Overwrite: overwrite,
		KeepBoth:  keepBoth,
		Sidecar:   uploadutil.Sidecars{Database: deps.Database(), FS: fsys, Serial: serial}.Attach,
		// An editor's save snapshots what it replaces (#1173).
		BeforeOverwrite: beforeSave(c, deps, serial),
	})
	// Files that landed before a failure are the caller's too, and the
	// clients have to hear about them however the request ended.
	grantOwners(c, deps, access, serial, written.Written)
	publishUpload(deps, serial, rootDir, written.Written)
	if err == nil {
		return serverutil.Ok().WithData(uploadedPaths(written.Written))
	}
	var failed *serverutil.Response
	switch {
	case errors.Is(err, uploadutil.ErrNoFiles), errors.Is(err, uploadutil.ErrInvalidBody):
		failed = serverutil.BadRequest(err)
	case nameTaken(err):
		failed = serverutil.Conflict(err)
	case errors.Is(err, vfs.ErrNotFound):
		// The device went away mid-upload.
		failed = serverutil.NotFound(err)
	default:
		failed = serverutil.InternalServerError(err)
	}
	return uploadFailed(failed, written.Written)
}

var uploadFilesRoute = serverutil.ApiRoute(
	"POST", "/files/upload", func(c *gin.Context) *serverutil.Response {
		return uploadFiles(c)
	},
)

var uploadFilesNestedRoute = serverutil.ApiRoute(
	"POST", "/files//upload/*rootDir", func(c *gin.Context) *serverutil.Response {
		return uploadFilesNested(c, c.Param("rootDir"))
	},
)
