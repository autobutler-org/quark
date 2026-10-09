package v0_files

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"

	"github.com/gin-gonic/gin"
)

type StatFileJSON struct {
	IsDir    bool   `json:"isDir"`
	FileType string `json:"fileType"` // Kept for older clients; route viewers by file name instead
	Name     string `json:"name"`
}

// statFile godoc
// @Summary Stat a file or directory
// @Description Returns filesystem metadata for the given files-relative path: whether it is a directory and its file type. Useful for deep-link resolution when the path extension alone is ambiguous (e.g. a folder named "things.qdoc").
// @Tags files
// @Produce json
// @Param filePath query string true "Files-relative path to stat"
// @Param serial query string false "Device serial number"
// @Success 200 {object} StatFileJSON
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/stat [get]
func statFile(c *gin.Context) *serverutil.Response {
	filePath := c.Query("filePath")

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(c.Query("serial"), filePath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	// The namespace of the device the request names: the serial used to be
	// dropped here, so a device path was stat-ed on the internal drive (#2642).
	fsys, err := fileutil.FilesVFS(deps.VFSRegistry(), c.Query("serial"))
	if err != nil {
		return fileError(err)
	}
	fi, err := fsys.Stat(c.Request.Context(), filePath)
	if errors.Is(err, vfs.ErrNotFound) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	// A folder is a folder whatever it is named: "things.qdoc/" is not a
	// document, which is what deep-link resolution asks this to tell apart.
	fileType := storageutil.FileTypeFolder
	if !fi.IsDir {
		fileType = storageutil.DetermineFileTypeFromPath(fi.Path)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(StatFileJSON{
		IsDir:    fi.IsDir,
		FileType: string(fileType),
		Name:     fi.Name,
	})
}

var statFileRoute = serverutil.ApiRoute(
	"GET", "/files/stat", statFile,
)
