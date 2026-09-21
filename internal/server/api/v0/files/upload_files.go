package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"

	"github.com/gin-gonic/gin"
)

// uploadFiles godoc
// @Summary Upload files to the top-level directory
// @Description Upload one or more files via multipart/form-data. Needs write access on the top-level directory; the caller owns each file the upload creates. A name already in use is a 409 unless overwrite or keepBoth says what to do about it.
// @Tags files
// @Accept multipart/form-data
// @Produce json
// @Param serial query string false "Device serial number to upload to"
// @Param overwrite query boolean false "Replace a file of the same name"
// @Param keepBoth query boolean false "Land under the first free name, e.g. file_(1).txt, when the name is taken"
// @Param file formData file true "File to upload"
// @Success 200 {object} serverutil.Response "OK"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 409 {object} serverutil.Response "Conflict"
// @Security BearerAuth
// @Router /files/upload [post]
func uploadFiles(c *gin.Context) *serverutil.Response {
	return uploadFilesNested(c, "")
}

// uploadFiles godoc
// @Summary Upload files to a nested directory
// @Description Upload one or more files via multipart/form-data. Needs write access on the directory; the caller owns each file the upload creates. A name already in use is a 409 unless overwrite or keepBoth says what to do about it.
// @Tags files
// @Accept multipart/form-data
// @Produce json
// @Param rootDir path string true "Directory to upload into"
// @Param serial query string false "Device serial number to upload to"
// @Param overwrite query boolean false "Replace a file of the same name"
// @Param keepBoth query boolean false "Land under the first free name, e.g. file_(1).txt, when the name is taken"
// @Param file formData file true "File to upload"
// @Success 200 {object} serverutil.Response "OK"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 409 {object} serverutil.Response "Conflict"
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
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	check := access.Check(serial, rootDir, accessutil.Write)
	if !check.Readable {
		return serverutil.NotFound(errNoAccess)
	}
	if !check.Allowed {
		return serverutil.Forbidden(errReadOnly)
	}
	reader, err := c.Request.MultipartReader()
	if err != nil {
		return serverutil.BadRequest(err)
	}
	dest := uploadDestination(deps)

	// VFS path: only when no serial is provided (VFS handles the local namespace).
	if fsys := dest.FilesVFS(serial); fsys != nil {
		written, err := uploadutil.WriteMultipartVFS(uploadutil.WriteMultipartParams{
			Ctx:       c.Request.Context(),
			FS:        fsys,
			Reader:    reader,
			RootDir:   rootDir,
			Overwrite: overwrite,
			KeepBoth:  keepBoth,
		})
		// Files that landed before a failure are the caller's too, and the
		// clients have to hear about them however the request ended.
		grantOwners(c, deps, access, serial, written.Written)
		publishUpload(deps, rootDir, written.Written)
		if err != nil {
			if nameTaken(err) {
				return serverutil.Conflict(err)
			}
			return serverutil.InternalServerError(err)
		}
		return serverutil.Ok()
	}

	// StorageService fallback (serial routing, etc.)
	written, err := deps.StorageService().UploadFilesStreamed(storageutil.UploadFilesStreamedParams{
		Reader:       reader,
		RootDir:      rootDir,
		DeviceSerial: serial,
		Overwrite:    overwrite,
		KeepBoth:     keepBoth,
	})
	grantOwners(c, deps, access, serial, written.Written)
	publishUpload(deps, rootDir, written.Written)
	if err != nil {
		if nameTaken(err) {
			return serverutil.Conflict(err)
		}
		return serverutil.BadRequest(err)
	}
	return serverutil.Ok()
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
